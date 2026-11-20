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
  export STUB_NUMBER=7
  export STUB_VIEWS="$ROOT/views"
  export STUB_UNKNOWN_VIEWS=0
  export MERGE_PR_UNKNOWN_DELAY=0
  export STUB_CHECKS="$ROOT/checks"
  export STUB_PENDING_CHECKS=0
  export MERGE_PR_CHECKS_DELAY=0

  mkdir -p "$ROOT/bin"
  cat > "$ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr checks")
    checks=$(( $(cat "$STUB_CHECKS" 2>/dev/null || echo 0) + 1 ))
    echo "$checks" > "$STUB_CHECKS"
    [ "$checks" -le "$STUB_PENDING_CHECKS" ] && exit 8
    exit "$STUB_CHECKS_STATUS"
    ;;
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
      mergeable="$STUB_MERGEABLE"
      views=$(( $(cat "$STUB_VIEWS" 2>/dev/null || echo 0) + 1 ))
      echo "$views" > "$STUB_VIEWS"
      [ "$views" -le "$STUB_UNKNOWN_VIEWS" ] && mergeable=UNKNOWN
      echo "{\"number\":$STUB_NUMBER,\"title\":\"feat\",\"url\":\"https://x/pull/7\",\"state\":\"OPEN\",\"mergeable\":\"$mergeable\",\"headRefName\":\"feat\",\"headRefOid\":\"$STUB_HEAD_OID\",\"baseRefName\":\"main\"}"
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
  [[ "$output" == *"checks fail"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "retries while checks are pending, then merges" {
  export STUB_PENDING_CHECKS=2
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checks pending, retry 2/40"* ]]
  [[ "$output" != *"checks pending, retry 3/40"* ]]
  [ -e "$STUB_MERGED" ]
}

@test "aborts when checks stay pending past the retry limit" {
  export STUB_PENDING_CHECKS=100
  export MERGE_PR_CHECKS_RETRIES=2
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks pending"* ]]
  [ "$(cat "$STUB_CHECKS")" -eq 3 ]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts when checks fail after being pending" {
  export STUB_PENDING_CHECKS=1
  export STUB_CHECKS_STATUS=1
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checks fail"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts when the PR is not mergeable" {
  export STUB_MERGEABLE=CONFLICTING
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mergeable=CONFLICTING"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "retries while mergeable is UNKNOWN, then merges" {
  export STUB_UNKNOWN_VIEWS=3
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry 3/20"* ]]
  [[ "$output" != *"retry 4/20"* ]]
  [ -e "$STUB_MERGED" ]
}

@test "aborts when mergeable stays UNKNOWN past the retry limit" {
  export STUB_UNKNOWN_VIEWS=100
  export MERGE_PR_UNKNOWN_RETRIES=2
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mergeable=UNKNOWN"* ]]
  [ "$(cat "$STUB_VIEWS")" -eq 3 ]
  [ ! -e "$STUB_MERGED" ]
}

@test "aborts before merging when the worktree has untracked files" {
  echo junk > "$WORKTREE/untracked"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ ! -e "$STUB_MERGED" ]
}

@test "reports no milestone for an ordinary PR" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"milestone="* ]]
}

@test "reports a milestone for every 100th PR number" {
  export STUB_NUMBER=1000
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"milestone=pr:1000"* ]]
}

@test "reports a milestone when the merge is the 100th commit on base" {
  for _ in $(seq 98); do git -C "$MAIN" commit -q --allow-empty -m filler; done
  git -C "$MAIN" push -q origin main
  git -C "$WORKTREE" rebase -q main
  git -C "$WORKTREE" push -qf origin feat
  export STUB_HEAD_OID; STUB_HEAD_OID="$(git -C "$WORKTREE" rev-parse HEAD)"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"milestone=commit:100"* ]]
}
