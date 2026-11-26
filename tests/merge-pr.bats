#!/usr/bin/env bats

setup_file() {
  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SCRIPT="$base/skills/merge-pr/merge-pr.sh"

  export TEMPLATE; TEMPLATE="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL="$TEMPLATE/gitconfig"
  cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	email = test@example.com
	name = test
[init]
	defaultBranch = main
[gc]
	auto = 0
EOF

  local remote="$TEMPLATE/remote.git"
  local main="$TEMPLATE/repo"
  local wt="$TEMPLATE/repo-feat"
  git init -q --bare "$remote"
  git clone -q "$remote" "$main" 2>/dev/null
  git -C "$main" remote set-url origin ../remote.git
  echo "see ../wiki" > "$main/AGENTS.md"
  git -C "$main" add -A && git -C "$main" commit -qm init && git -C "$main" push -q origin main
  git -C "$main" worktree add -q -b feat "$wt"
  echo change > "$wt/file"
  git -C "$wt" add -A && git -C "$wt" commit -qm feat && git -C "$wt" push -q origin feat

  export TEMPLATE_HEAD_OID; TEMPLATE_HEAD_OID="$(git -C "$wt" rev-parse HEAD)"

  mkdir -p "$TEMPLATE/bin"
  cat > "$TEMPLATE/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr checks")
    checks=0
    [ -f "$STUB_CHECKS" ] && read -r checks < "$STUB_CHECKS"
    checks=$((checks + 1))
    echo "$checks" > "$STUB_CHECKS"
    [ "$checks" -le "$STUB_PENDING_CHECKS" ] && exit 8
    exit "$STUB_CHECKS_STATUS"
    ;;
  "pr merge")
    : > "$STUB_MERGED"
    new_sha="$(git -C "$STUB_REMOTE" commit-tree feat^{tree} -p main -m "feat (#7)")"
    git -C "$STUB_REMOTE" update-ref refs/heads/main "$new_sha"
    ;;
  "pr view")
    if [[ "$*" == *mergeCommit* ]]; then
      echo "{\"mergeCommit\":{\"oid\":\"$(git -C "$STUB_REMOTE" rev-parse main)\"}}"
    else
      mergeable="$STUB_MERGEABLE"
      views=0
      [ -f "$STUB_VIEWS" ] && read -r views < "$STUB_VIEWS"
      views=$((views + 1))
      echo "$views" > "$STUB_VIEWS"
      [ "$views" -le "$STUB_UNKNOWN_VIEWS" ] && mergeable=UNKNOWN
      echo "{\"number\":$STUB_NUMBER,\"title\":\"feat\",\"url\":\"https://x/pull/7\",\"state\":\"OPEN\",\"mergeable\":\"$mergeable\",\"headRefName\":\"feat\",\"headRefOid\":\"$STUB_HEAD_OID\",\"baseRefName\":\"main\"}"
    fi
    ;;
esac
STUB
  chmod +x "$TEMPLATE/bin/gh"
}

teardown_file() { rm -rf "$TEMPLATE"; }

setup() {
  ROOT="$(mktemp -d)"
  REMOTE="$ROOT/remote.git"
  MAIN="$ROOT/repo"
  WORKTREE="$ROOT/repo-feat"
  cp -R "$TEMPLATE/remote.git" "$TEMPLATE/repo" "$TEMPLATE/repo-feat" "$ROOT/"
  printf 'gitdir: %s/.git/worktrees/repo-feat\n' "$MAIN" > "$WORKTREE/.git"
  printf '%s/.git\n' "$WORKTREE" > "$MAIN/.git/worktrees/repo-feat/gitdir"

  export STUB_REMOTE="$REMOTE"
  export STUB_HEAD_OID="$TEMPLATE_HEAD_OID"
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

  export PATH="$TEMPLATE/bin:$PATH"
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
  {
    printf 'commit refs/heads/main\nmark :1\ncommitter test <test@example.com> 1700000001 +0000\ndata 6\nfiller\nfrom refs/heads/main^0\n'
    local i
    for ((i = 2; i <= 98; i++)); do
      printf 'commit refs/heads/main\nmark :%d\ncommitter test <test@example.com> %d +0000\ndata 6\nfiller\nfrom :%d\n' "$i" "$((1700000000 + i))" "$((i - 1))"
    done
  } | git -C "$MAIN" fast-import --quiet
  local new_feat
  new_feat="$(git -C "$MAIN" commit-tree feat^{tree} -p main -m feat)"
  git -C "$MAIN" update-ref refs/heads/feat "$new_feat"
  git -C "$MAIN" push -qf origin main feat
  export STUB_HEAD_OID="$new_feat"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"milestone=commit:100"* ]]
}
