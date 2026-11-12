#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="$(cd "$SKILL_DIR/../../.." && pwd)"
SANDBOX_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)/verify-prune-worktrees"
EVIDENCE_BASE="${VERIFY_PRUNE_EVIDENCE_DIR:-$HOME/.cache/verify-prune-worktrees}"
PRUNE_BIN="${PRUNE_WORKTREES_BIN:-$DOTFILES/bin/prune-worktrees}"
MARKER=".verify-prune-worktrees-fixture"

usage() {
  cat <<EOF
usage: verify.sh <command> <run-id> [args]

  fixture <run-id>                  build a fresh sandbox fixture
  doctor  <run-id>                  read-only health check of the sandbox
  run     <run-id> <label> [-- args] run prune-worktrees on the sandbox root, capture evidence
  paths   <run-id>                  print sandbox and evidence paths
  cleanup <run-id>                  delete the sandbox (evidence is kept)
EOF
  exit 2
}

[ $# -ge 2 ] || usage
COMMAND="$1"
RUN_ID="$2"
shift 2
case "$RUN_ID" in
  *[!A-Za-z0-9._-]*|"") echo "run-id must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
esac

SANDBOX="$SANDBOX_BASE/$RUN_ID"
ROOT="$SANDBOX/root"
REMOTES="$SANDBOX/remotes"
EVIDENCE="$EVIDENCE_BASE/$RUN_ID"

export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0

commit() {
  local repo="$1" message="$2"
  local file="${message%% *}.txt"
  echo "$message" >> "$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -q -m "$message"
}

build_fixture() {
  if [ -e "$SANDBOX" ]; then
    echo "sandbox already exists: $SANDBOX (run cleanup first)" >&2
    exit 1
  fi
  mkdir -p "$ROOT" "$REMOTES"
  cat > "$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = verify-prune-worktrees
	email = verify@example.invalid
[init]
	defaultBranch = main
[commit]
	gpgsign = false
[advice]
	detachedHead = false
EOF
  touch "$ROOT/$MARKER"

  git init -q --bare "$REMOTES/app.git"
  git init -q "$ROOT/app"
  local app="$ROOT/app"
  commit "$app" "initial"
  git -C "$app" remote add origin "$REMOTES/app.git"
  git -C "$app" push -q -u origin main
  git -C "$app" remote set-head origin main

  local name
  for name in merged squashed gone active dirty-merged; do
    git -C "$app" switch -q -c "feat-$name" main
    commit "$app" "$name work 1"
    [ "$name" = squashed ] && commit "$app" "$name work 2"
    git -C "$app" push -q -u origin "feat-$name"
  done
  git -C "$app" switch -q -c feat-local main
  commit "$app" "local-only work"
  git -C "$app" switch -q -c feat-detached main
  commit "$app" "detached work"
  local detached_sha
  detached_sha="$(git -C "$app" rev-parse HEAD)"
  git -C "$app" switch -q main
  git -C "$app" branch -q -D feat-detached
  git -C "$app" branch -q feat-empty main
  git -C "$app" branch -q feat-locked main
  commit "$app" "main moves on"
  git -C "$app" branch -q feat-missing

  git -C "$app" merge -q --no-ff -m "merge feat-merged" feat-merged
  git -C "$app" merge -q --no-ff -m "merge feat-dirty-merged" feat-dirty-merged
  git -C "$app" merge -q --squash feat-squashed
  git -C "$app" commit -q -m "squash feat-squashed"
  git -C "$app" push -q origin main

  mkdir -p "$ROOT/wt"
  for name in merged squashed gone active dirty-merged local empty locked missing; do
    git -C "$app" worktree add -q "$ROOT/wt/$name" "feat-$name"
  done
  git -C "$app" worktree add -q --detach "$ROOT/wt/detached" "$detached_sha"
  git -C "$app" worktree lock "$ROOT/wt/locked"
  echo scratch > "$ROOT/wt/dirty-merged/untracked.txt"
  rm -rf "$ROOT/wt/missing"
  git -C "$REMOTES/app.git" branch -q -D feat-gone

  git init -q "$ROOT/nested/lib"
  commit "$ROOT/nested/lib" "lib initial"
  mkdir -p "$ROOT/nested/lib/inner"
  git init -q "$ROOT/nested/lib/inner/shadowed"
  commit "$ROOT/nested/lib/inner/shadowed" "shadowed initial"
  git -C "$ROOT/nested/lib/inner/shadowed" worktree add -q -b feat-shadowed "$ROOT/wt/shadowed"

  git init -q "$ROOT/node_modules/skipped"
  commit "$ROOT/node_modules/skipped" "skipped initial"
  git -C "$ROOT/node_modules/skipped" worktree add -q -b feat-skipped "$ROOT/wt/skipped"

  git init -q "$ROOT/noremote"
  commit "$ROOT/noremote" "noremote initial"
  git -C "$ROOT/noremote" worktree add -q -b feat-noremote "$ROOT/wt/noremote"

  echo "fixture ready: $ROOT"
}

require_fixture() {
  if [ ! -f "$ROOT/$MARKER" ]; then
    echo "no fixture at $ROOT — run: verify.sh fixture $RUN_ID" >&2
    exit 1
  fi
}

snapshot() {
  local out="$1" repo
  {
    for repo in "$ROOT/app" "$ROOT/nested/lib" "$ROOT/nested/lib/inner/shadowed" "$ROOT/node_modules/skipped" "$ROOT/noremote"; do
      echo "## $repo"
      git -C "$repo" worktree list --porcelain
      git -C "$repo" branch -a -vv --no-color
      echo
    done
    echo "## remote branches (app.git)"
    git -C "$REMOTES/app.git" for-each-ref --format='%(refname)' refs/heads
    echo
    echo "## directories under wt/"
    ls -1A "$ROOT/wt"
  } > "$out" 2>&1
}

run_tool() {
  [ $# -ge 1 ] || usage
  local label="$1"
  shift
  [ "${1:-}" = "--" ] && shift
  require_fixture
  case "$label" in
    *[!A-Za-z0-9._-]*|"") echo "label must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
  esac
  local dir="$EVIDENCE/$label"
  if [ -e "$dir" ]; then
    echo "evidence label already used: $dir" >&2
    exit 1
  fi
  mkdir -p "$dir"
  printf '%q ' "$PRUNE_BIN" "$ROOT" "$@" > "$dir/command.txt"
  echo >> "$dir/command.txt"
  snapshot "$dir/state-before.txt"
  local exit_code=0
  "$PRUNE_BIN" "$ROOT" "$@" > "$dir/stdout.txt" 2> "$dir/stderr.txt" || exit_code=$?
  echo "$exit_code" > "$dir/exit-code.txt"
  snapshot "$dir/state-after.txt"
  diff -u "$dir/state-before.txt" "$dir/state-after.txt" > "$dir/state.diff" || true
  echo "\$ $(cat "$dir/command.txt")"
  cat "$dir/stdout.txt"
  cat "$dir/stderr.txt" >&2
  echo "exit=$exit_code  evidence=$dir"
}

doctor() {
  local failures=0
  check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
      echo "OK    $label"
    else
      echo "FAIL  $label"
      failures=$((failures + 1))
    fi
  }
  check "python3 >= 3.9 (str.removeprefix)" python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))'
  check "git on PATH" git --version
  check "prune-worktrees executable: $PRUNE_BIN" test -x "$PRUNE_BIN"
  check "prune-worktrees --help parses" "$PRUNE_BIN" --help
  check "fixture marker at $ROOT" test -f "$ROOT/$MARKER"
  check "sandbox root is not ~/work" test "$ROOT" != "$HOME/work"
  check "sandbox gitconfig isolates identity" test -f "$GIT_CONFIG_GLOBAL"
  check "app origin is a local path (fetch stays offline)" test -d "$(git -C "$ROOT/app" remote get-url origin 2>/dev/null || echo /nonexistent)"
  check "app origin/HEAD resolves" git -C "$ROOT/app" rev-parse --verify origin/HEAD
  if [ -L "$HOME/.local/bin/prune-worktrees" ]; then
    echo "INFO  ~/.local/bin/prune-worktrees -> $(readlink "$HOME/.local/bin/prune-worktrees")"
  else
    echo "INFO  ~/.local/bin/prune-worktrees not installed (run ./install.sh to link)"
  fi
  echo "INFO  evidence dir: $EVIDENCE"
  [ "$failures" -eq 0 ]
}

cleanup() {
  case "$SANDBOX" in
    "$SANDBOX_BASE"/?*) ;;
    *) echo "refusing to delete unexpected path: $SANDBOX" >&2; exit 1 ;;
  esac
  if [ ! -e "$SANDBOX" ]; then
    echo "nothing to clean: $SANDBOX"
  elif [ -f "$ROOT/$MARKER" ] || [ ! -e "$ROOT" ]; then
    chmod -R u+w "$SANDBOX" 2> /dev/null || true
    rm -rf "$SANDBOX"
    echo "removed sandbox: $SANDBOX"
  else
    echo "refusing to delete $SANDBOX: no fixture marker" >&2
    exit 1
  fi
  if [ -d "$EVIDENCE" ]; then
    echo "evidence kept: $EVIDENCE"
  fi
}

case "$COMMAND" in
  fixture) build_fixture ;;
  doctor) doctor ;;
  run) run_tool "$@" ;;
  paths) printf 'sandbox=%s\nroot=%s\nevidence=%s\n' "$SANDBOX" "$ROOT" "$EVIDENCE" ;;
  cleanup) cleanup ;;
  *) usage ;;
esac
