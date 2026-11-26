#!/usr/bin/env bash
set -euo pipefail

die() { echo "ABORT: $*" >&2; exit 1; }
note() { echo "note=$*"; }

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
    checks=pass
  elif [ "$status" -eq 8 ]; then
    checks=pending
  else
    checks=fail
  fi
}

fetch_pr() {
  pr_json=$(gh pr view ${1:+"$1"} --json number,title,url,state,mergeable,headRefName,headRefOid,baseRefName)
  {
    IFS= read -r -d '' number
    IFS= read -r -d '' title
    IFS= read -r -d '' url
    IFS= read -r -d '' state
    IFS= read -r -d '' mergeable
    IFS= read -r -d '' branch
    IFS= read -r -d '' head_oid
    IFS= read -r -d '' base
  } < <(
    jq -j '(.number, .title, .url, .state, .mergeable, .headRefName, .headRefOid, .baseRefName) | tostring + "\u0000"' <<<"$pr_json"
  )
}

fetch_pr "${1:-}"

retries="${MERGE_PR_UNKNOWN_RETRIES:-20}"
delay="${MERGE_PR_UNKNOWN_DELAY:-15}"
attempt=0
while [ "$mergeable" = UNKNOWN ] && [ "$attempt" -lt "$retries" ]; do
  attempt=$((attempt + 1))
  echo "waiting: PR #$number mergeable=UNKNOWN, retry $attempt/$retries in ${delay}s" >&2
  if [ "$delay" != 0 ]; then sleep "$delay"; fi
  fetch_pr "$number"
done

[ "$state" = OPEN ] || die "PR #$number is $state"
[ "$mergeable" = MERGEABLE ] || die "PR #$number mergeable=$mergeable"

checks_retries="${MERGE_PR_CHECKS_RETRIES:-40}"
checks_delay="${MERGE_PR_CHECKS_DELAY:-30}"
attempt=0
checks_state "$number"
while [ "$checks" = pending ] && [ "$attempt" -lt "$checks_retries" ]; do
  attempt=$((attempt + 1))
  echo "waiting: PR #$number checks pending, retry $attempt/$checks_retries in ${checks_delay}s" >&2
  if [ "$checks_delay" != 0 ]; then sleep "$checks_delay"; fi
  checks_state "$number"
done
[ "$checks" = pass ] || die "PR #$number checks $checks (gh pr checks $number)"

{
  IFS= read -r main_dir
  IFS= read -r main_branch
  IFS= read -r worktree
} < <(
  git worktree list --porcelain | awk -v ref="branch refs/heads/$branch" '
    /^worktree /{
      path = substr($0, 10)
      stanza++
      if (stanza == 1) main = path
    }
    stanza == 1 && /^branch refs\/heads\//{
      main_branch = substr($0, 19)
    }
    $0 == ref && wt == "" {wt = path}
    END {print main; print main_branch; print wt}'
)

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
echo "title=$title"
echo "branch=$branch"
echo "sha=$sha"

if git -C "$main_dir" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  git -C "$main_dir" push -q origin --delete "$branch" || note "remote branch delete failed"
fi

branch_in_worktree=0
if [ "$worktree" = "$main_dir" ]; then
  branch_in_worktree=1
  note "$branch is checked out in $main_dir; switch it to $base by hand"
elif [ -n "$worktree" ]; then
  if git -C "$main_dir" worktree remove "$worktree" 2>/dev/null; then
    echo "worktree_removed=$worktree"
  else
    branch_in_worktree=1
    note "worktree $worktree not removed (untracked files?); ask before --force"
  fi
fi

if [ "$branch_in_worktree" -eq 0 ] && [ -n "${local_oid:-}" ]; then
  git -C "$main_dir" branch -q -D "$branch"
fi
git -C "$main_dir" worktree prune

if [ "$main_branch" = "$base" ]; then
  git -C "$main_dir" pull -q --ff-only || note "$main_dir pull --ff-only failed"
else
  note "$main_dir not on $base; not pulled"
fi

report_milestone pr "$number"
if commit_count=$(git -C "$main_dir" rev-list --count "$sha" 2>/dev/null); then
  report_milestone commit "$commit_count"
fi

wiki_dir="${main_dir%/*}/wiki"
if [ -f "$main_dir/AGENTS.md" ] && [[ "$(<"$main_dir/AGENTS.md")" == *'../wiki'* ]]; then
  echo "wiki=$wiki_dir"
fi
