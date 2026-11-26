# Merged pull requests

A branch merged through a PR into a base other than `<remote>/HEAD` (for example a long-lived `dev-*` integration branch) is not an ancestor of the default branch, so the git checks alone call it ACTIVE. For every branch that is still unmerged after the ancestor and squash checks, `prune-worktrees` runs `gh pr list --head <branch> --state merged` from the repo. If a merged PR's head commit contains the local tip, the worktree is MERGED and its branch is deleted on `--remove` like any other merged branch. `--no-gh` skips the lookup.

## Sub-features

- `pr-merged` reports MERGED `PR #<n> merged into <base>` when the local tip is the PR head or an ancestor of it.
- `pr-ahead` keeps a branch with commits after the merged PR head as ACTIVE `PR #<n> merged into <base>, local commits after it`, so `--remove` never drops them.
- `pr-scope` calls `gh` only for worktrees with a branch that are not already MERGED, SQUASHED, MISSING, LOCKED, or UNKNOWN.
- `pr-no-gh` with `--no-gh`, makes no `gh` calls and falls back to the git-only status.
- `pr-unavailable` treats a missing `gh` binary, a non-zero exit (not a GitHub repo, no auth), or unparseable output as "no merged PR".

## How to get to it (user POV)

- `prune-worktrees <root>` (queries GitHub through the user's `gh` auth)
- `prune-worktrees <root> --no-gh`
- `PRUNE_WORKTREES_GH=<path>` overrides the `gh` binary.

## Driving it with verify.sh

Preconditions:

- Fresh fixture. `$V doctor $RUN` shows the `gh` stub check as OK.

- **Merged into a non-default base.** Run `$V run $RUN pr -- --no-fetch --all`. `feat-pr-merged` is MERGED `PR #101 merged into release`. `feat-pr-ahead` is ACTIVE `PR #102 merged into release, local commits after it`. `gh-calls.txt` has exactly 5 lines, all from `root/app`: `feat-active`, `feat-gone`, `feat-local`, `feat-pr-ahead`, `feat-pr-merged` (order varies). `state.diff` is empty.
- **Skip GitHub.** Run `$V run $RUN pr-nogh -- --no-fetch --all --no-gh`. Both `feat-pr-merged` and `feat-pr-ahead` are ACTIVE `upstream exists, unmerged`. `gh-calls.txt` is empty. stderr says `4 dead`.
- **Removal.** Covered by `remove.md`: `feat-pr-merged` is `removed; branch deleted`, and `wt/pr-ahead` survives.

## Gotchas

- Against `~/work` this is one real `gh` API call per candidate worktree, run `--jobs` at a time. Expect a few seconds on top of the fetch.
- The ancestor check needs the PR head commit locally. If the PR branch was deleted on the remote and never fetched, the commit is unknown, the check fails, and the worktree stays ACTIVE. That is the safe direction.
- A closed-but-unmerged PR is never a match; only `--state merged` is queried.
- `gh` resolves the GitHub repo from the cwd's remotes. In a repo with several GitHub remotes, it uses `gh repo set-default` if set, which may not be `--remote`.
- Detached worktrees have no branch to look up, so they stay ACTIVE.
