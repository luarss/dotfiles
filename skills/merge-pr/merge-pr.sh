#!/usr/bin/env bash
set -euo pipefail

die() { echo "ABORT: $*" >&2; exit 1; }
note() { echo "note=$*"; }

main_worktree() {
  git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}'
}

branch_worktree() {
  local branch="$1"
  git worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '
    /^worktree /{path = substr($0, 10)}
    $0 == ref {print path; exit}'
}

report_milestone() {
  local kind="$1" count="$2"
  if [ "$count" -gt 0 ] && [ $((count % 100)) -eq 0 ]; then
    echo "milestone=$kind:$count"
  fi
}

checks_state() {
  local number="$1" output status=0
  output=$(gh pr checks "$number" 2>&1) || status=$?
  if [ "$status" -eq 0 ] || [[ "$output" == *"no checks reported"* ]]; then
    echo pass
  elif [ "$status" -eq 8 ]; then
    echo pending
  else
    echo fail
  fi
}

fetch_pr() {
  pr_json=$(gh pr view ${1:+"$1"} --json number,title,url,state,mergeable,headRefName,headRefOid,baseRefName)
}
field() { jq -r ".$1" <<<"$pr_json"; }

fetch_pr "${1:-}"
number=$(field number)

retries="${MERGE_PR_UNKNOWN_RETRIES:-20}"
delay="${MERGE_PR_UNKNOWN_DELAY:-15}"
attempt=0
while [ "$(field mergeable)" = UNKNOWN ] && [ "$attempt" -lt "$retries" ]; do
  attempt=$((attempt + 1))
  echo "waiting: PR #$number mergeable=UNKNOWN, retry $attempt/$retries in ${delay}s" >&2
  sleep "$delay"
  fetch_pr "$number"
done

url=$(field url)
branch=$(field headRefName)
head_oid=$(field headRefOid)
base=$(field baseRefName)

[ "$(field state)" = OPEN ] || die "PR #$number is $(field state)"
[ "$(field mergeable)" = MERGEABLE ] || die "PR #$number mergeable=$(field mergeable)"

checks_retries="${MERGE_PR_CHECKS_RETRIES:-40}"
checks_delay="${MERGE_PR_CHECKS_DELAY:-30}"
attempt=0
checks=$(checks_state "$number")
while [ "$checks" = pending ] && [ "$attempt" -lt "$checks_retries" ]; do
  attempt=$((attempt + 1))
  echo "waiting: PR #$number checks pending, retry $attempt/$checks_retries in ${checks_delay}s" >&2
  sleep "$checks_delay"
  checks=$(checks_state "$number")
done
[ "$checks" = pass ] || die "PR #$number checks $checks (gh pr checks $number)"

main_dir=$(main_worktree)
worktree=$(branch_worktree "$branch")

if [ -n "$worktree" ]; then
  [ -z "$(git -C "$worktree" status --porcelain)" ] || die "uncommitted changes in $worktree"
fi
if local_oid=$(git -C "$main_dir" rev-parse -q --verify "refs/heads/$branch"); then
  [ "$local_oid" = "$head_oid" ] || die "local $branch ($local_oid) differs from PR head ($head_oid)"
fi

gh pr merge "$number" --squash --match-head-commit "$head_oid" >/dev/null
sha=$(gh pr view "$number" --json mergeCommit | jq -r .mergeCommit.oid)

echo "pr=$number"
echo "url=$url"
echo "title=$(field title)"
echo "branch=$branch"
echo "sha=$sha"

if git -C "$main_dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  git -C "$main_dir" push -q origin --delete "$branch" || note "remote branch delete failed"
fi

if [ "$worktree" = "$main_dir" ]; then
  note "$branch is checked out in $main_dir; switch it to $base by hand"
elif [ -n "$worktree" ]; then
  if git -C "$main_dir" worktree remove "$worktree" 2>/dev/null; then
    echo "worktree_removed=$worktree"
  else
    note "worktree $worktree not removed (untracked files?); ask before --force"
  fi
fi

if [ -z "$(branch_worktree "$branch")" ] && [ -n "${local_oid:-}" ]; then
  git -C "$main_dir" branch -q -D "$branch"
fi
git -C "$main_dir" worktree prune

if [ "$(git -C "$main_dir" branch --show-current)" = "$base" ]; then
  git -C "$main_dir" pull -q --ff-only || note "$main_dir pull --ff-only failed"
else
  note "$main_dir not on $base; not pulled"
fi

report_milestone pr "$number"
if commit_count=$(git -C "$main_dir" rev-list --count "$sha" 2>/dev/null); then
  report_milestone commit "$commit_count"
fi

wiki_dir="$(dirname "$main_dir")/wiki"
if grep -qs '\.\./wiki' "$main_dir/AGENTS.md"; then
  echo "wiki=$wiki_dir"
fi
