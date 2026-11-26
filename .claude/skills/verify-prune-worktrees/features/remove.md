# Remove dead worktrees

With `--remove`, every dead worktree (MISSING, MERGED, SQUASHED, GONE) is cleaned up. MISSING ones go through `git worktree prune`, and the rest through `git worktree remove`. Dirty dead worktrees are skipped unless you pass `--force`. The local branch of a removed MERGED or SQUASHED worktree is force-deleted by default; `--keep-branches` keeps it. `--delete-branches` also deletes the branch of GONE and MISSING worktrees. The two flags are mutually exclusive. Live worktrees are never touched.

## Sub-features

- `remove-clean` removes clean MERGED, SQUASHED, and GONE worktrees and reports `removed`.
- `remove-prune-missing` prunes MISSING entries and reports `pruned`.
- `remove-skip-dirty` leaves a dirty dead worktree and reports `skipped: dirty (use --force)`.
- `remove-force` removes a dirty dead worktree with `--force`.
- `remove-default-branches` deletes the branch of removed MERGED and SQUASHED worktrees and reports `branch deleted`, but keeps GONE and MISSING branches.
- `remove-keep-branches` keeps every local branch with `--keep-branches`.
- `remove-delete-branches` also deletes GONE and MISSING branches with `--delete-branches`.
- `remove-spares-live` leaves ACTIVE, NO_COMMITS, LOCKED, and UNKNOWN worktrees intact.

## How to get to it (user POV)

- `prune-worktrees <root> --remove`
- `prune-worktrees <root> --remove --force`
- `prune-worktrees <root> --remove --keep-branches`
- `prune-worktrees <root> --remove --delete-branches` (combinable with `--force`)

## Driving it with verify.sh

Preconditions:

- A fresh, unmutated fixture. This recipe mutates it, so cleanup after.

- **Remove without force.** Run `$V run $RUN remove -- --remove`. Exit `0`. REASONs:
  - `feat-merged`, `feat-squashed`, `feat-pr-merged`: `...; removed; branch deleted`
  - `feat-gone`: `...; removed`
  - `feat-missing`: `...; pruned`
  - `feat-dirty-merged`: `...; skipped: dirty (use --force)`
  
  Stderr shows `3 repos, 13 linked worktrees, 6 dead: 5 removed, 3 branches deleted, 1 skipped (dirty, use --force)`, with no `dry run` suffix. In `state.diff`, the worktree entries and `wt/` dirs for gone, merged, squashed, missing, and pr-merged disappear. `wt/dirty-merged` stays. The `feat-merged`, `feat-squashed`, and `feat-pr-merged` branch lines disappear; `feat-gone`, `feat-missing`, and `feat-dirty-merged` are still listed.
- **Force with branch deletion.** Run `$V run $RUN remove-force -- --remove --force --delete-branches`. You get one row: `feat-dirty-merged`, `...; removed; branch deleted`. In `state.diff`, the `wt/dirty-merged` worktree, its dir, and the `feat-dirty-merged` branch line disappear. Stderr shows `3 repos, 8 linked worktrees, 1 dead: 1 removed, 1 branches deleted`.
- **Live worktrees intact.** In `remove-force/state-after.txt`, the worktrees for active, detached, empty, local, locked, noremote, and pr-ahead are still listed, and their dirs exist under `wt/`.

## Gotchas

- Branch deletion uses `git branch -D` (SQUASHED branches are not ancestors of the default branch, so `-d` would refuse). With `--delete-branches` this **deletes unmerged commits** on GONE and MISSING branches without warning. Check the report before combining it with `--remove`.
- Branches whose worktree was removed in an earlier run are not revisited. The tool only acts on branches that still have a worktree, so `feat-gone` and `feat-missing` stay as local branches after step 1 even when step 2 passes `--delete-branches`.
- `--force`, `--keep-branches`, and `--delete-branches` do nothing without `--remove`. Their output is identical to a dry run.
- MISSING removal runs a repo-wide `git worktree prune`, which also prunes other stale entries in that repo.
