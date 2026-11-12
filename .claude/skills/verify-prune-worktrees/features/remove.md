# Remove dead worktrees

With `--remove`, every dead worktree (MISSING, MERGED, SQUASHED, GONE) is cleaned up. MISSING ones go through `git worktree prune`, and the rest through `git worktree remove`. Dirty dead worktrees are skipped unless you pass `--force`. `--delete-branches` also force-deletes the local branch. Live worktrees are never touched.

## Sub-features

- `remove-clean` removes clean MERGED, SQUASHED, and GONE worktrees and reports `removed`.
- `remove-prune-missing` prunes MISSING entries and reports `pruned`.
- `remove-skip-dirty` leaves a dirty dead worktree and reports `skipped: dirty (use --force)`.
- `remove-force` removes a dirty dead worktree with `--force`.
- `remove-delete-branches` deletes the local branch and reports `branch deleted`.
- `remove-spares-live` leaves ACTIVE, NO_COMMITS, LOCKED, and UNKNOWN worktrees intact.

## How to get to it (user POV)

- `prune-worktrees <root> --remove`
- `prune-worktrees <root> --remove --force`
- `prune-worktrees <root> --remove --delete-branches` (combinable with `--force`)

## Driving it with verify.sh

Preconditions:

- A fresh, unmutated fixture. This recipe mutates it, so cleanup after.

- **Remove without force.** Run `$V run $RUN remove -- --remove`. Exit `0`. REASONs:
  - `feat-gone`, `feat-merged`, `feat-squashed`: `...; removed`
  - `feat-missing`: `...; pruned`
  - `feat-dirty-merged`: `...; skipped: dirty (use --force)`
  
  The summary has no `dry run` suffix. In `state.diff`, the worktree entries and `wt/` dirs for gone, merged, squashed, and missing disappear. `wt/dirty-merged` stays. All local branches are still listed.
- **Force with branch deletion.** Run `$V run $RUN remove-force -- --remove --force --delete-branches`. You get one row: `feat-dirty-merged`, `...; removed; branch deleted`. In `state.diff`, the `wt/dirty-merged` worktree, its dir, and the `feat-dirty-merged` branch line disappear. Stderr shows `3 repos, 7 linked worktrees, 1 dead`.
- **Live worktrees intact.** In `remove-force/state-after.txt`, the worktrees for active, detached, empty, local, locked, and noremote are still listed, and their dirs exist under `wt/`.

## Gotchas

- `--delete-branches` uses `git branch -D`, so it **deletes unmerged commits** on GONE branches without warning. Check the report before combining it with `--remove`.
- Branches whose worktree was removed in an earlier run without `--delete-branches` are not revisited. The tool only acts on branches that still have a worktree, so `feat-gone`, `feat-merged`, and the rest stay as local branches after step 1.
- `--force` and `--delete-branches` do nothing without `--remove`. Their output is identical to a dry run.
- MISSING removal runs a repo-wide `git worktree prune`, which also prunes other stale entries in that repo.
