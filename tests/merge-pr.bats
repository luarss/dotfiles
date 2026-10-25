#!/usr/bin/env bats

setup() {
  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$base/skills/merge-pr/merge-pr.sh"

  ROOT="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL="$ROOT/gitconfig"
  git config --global user.email test@example.com
  git config --global user.name test
  git config --global init.defaultBranch main

  REMOTE="$ROOT/remote.git"
  MAIN="$ROOT/repo"
  WORKTREE="$ROOT/repo-feat"
  git init -q --bare "$REMOTE"
  git clone -q "$REMOTE" "$MAIN" 2>/dev/null
  echo "see ../wiki" > "$MAIN/AGENTS.md"
  git -C "$MAIN" add -A && git -C "$MAIN" commit -qm init && git -C "$MAIN" push -q origin main
  git -C "$MAIN" worktree add -q -b feat "$WORKTREE"
  echo change > "$WORKTREE/file"
  git -C "$WORKTREE" add -A && git -C "$WORKTREE" commit -qm feat && git -C "$WORKTREE" push -q origin feat

  export STUB_REMOTE="$REMOTE"
  export STUB_HEAD_OID; STUB_HEAD_OID="$(git -C "$WORKTREE" rev-parse HEAD)"
  export STUB_MERGED="$ROOT/merged"
  export STUB_CHECKS_STATUS=0
  export STUB_MERGEABLE=MERGEABLE

  mkdir -p "$ROOT/bin"
  cat > "$ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr checks") exit "$STUB_CHECKS_STATUS" ;;
  "pr merge")
    touch "$STUB_MERGED"
    clone="$(mktemp -d)"
    git clone -q "$STUB_REMOTE" "$clone" 2>/dev/null
    git -C "$clone" merge -q --squash origin/feat >/dev/null
    git -C "$clone" commit -qm "feat (#7)"
    git -C "$clone" push -q origin main
    ;;
  "pr view")
    if [[ "$*" == *mergeCommit* ]]; then
      echo "{\"mergeCommit\":{\"oid\":\"$(git -C "$STUB_REMOTE" rev-parse main)\"}}"
    else
      echo "{\"number\":7,\"title\":\"feat\",\"url\":\"https://x/pull/7\",\"state\":\"OPEN\",\"mergeable\":\"$STUB_MERGEABLE\",\"headRefName\":\"feat\",\"headRefOid\":\"$STUB_HEAD_OID\",\"baseRefName\":\"main\"}"
    fi
    ;;
esac
STUB
  chmod +x "$ROOT/bin/gh"
  export PATH="$ROOT/bin:$PATH"
  cd "$MAIN"
}

teardown() { rm -rf "$ROOT"; }

@test "merges, deletes branches and worktree, fast-forwards main" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha=$(git -C "$REMOTE" rev-parse main)"* ]]
  [[ "$output" == *"wiki=$ROOT/wiki"* ]]
  [ ! -d "$WORKTREE" ]
  ! git -C "$MAIN" rev-parse -q --verify refs/heads/feat
  ! git -C "$REMOTE" rev-parse -q --verify refs/heads/feat
  [ "$(git -C "$MAIN" rev-parse HEAD)" = "$(git -C "$REMOTE" rev-parse main)" ]
}

@test "aborts before merging when the worktree is dirty" {
  echo dirty > "$WORKTREE/file"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts before merging when local branch has unpushed commits" {
  git -C "$WORKTREE" commit -q --allow-empty -m unpushed
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs from PR head"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts when checks fail" {
  export STUB_CHECKS_STATUS=1
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks not green"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts when the PR is not mergeable" {
  export STUB_MERGEABLE=CONFLICTING
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mergeable=CONFLICTING"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts before merging when the worktree has untracked files" {
  echo junk > "$WORKTREE/untracked"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ ! -e "$STUB_MERGED" ]
}
