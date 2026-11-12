# Classify worktrees

Running `prune-worktrees` without `--remove` prints a table of linked worktrees with a status and reason, then a summary on stderr. It changes nothing in the worktrees. By default only dead worktrees (MISSING, MERGED, SQUASHED, GONE) are listed, and `--all` adds ACTIVE, NO_COMMITS, LOCKED, and UNKNOWN.

## Sub-features

- `classify-dead` lists only dead worktrees by default.
- `classify-all` lists every linked worktree with `--all`.
- `classify-merged` reports a tip contained in `<remote>/HEAD` as MERGED.
- `classify-squashed` reports a squash-merged branch as SQUASHED.
- `classify-missing` reports a deleted worktree dir as MISSING.
- `classify-active` reports the three ACTIVE reasons: upstream exists, local-only, and detached HEAD.
- `classify-no-commits` reports a never-pushed branch with no new commits as NO_COMMITS (not dead).
- `classify-locked` reports a locked worktree as LOCKED.
- `classify-unknown` reports a repo with no remote default branch as UNKNOWN.
- `classify-dirty` sets DIRTY=`yes` when there are uncommitted or untracked files.
- `classify-summary` prints `N repos, M linked worktrees, K dead (D dirty) — dry run, pass --remove to delete` on stderr.

## How to get to it (user POV)

- `prune-worktrees`, which scans `~/work`. **Not used in verification.**
- `prune-worktrees <root>`
- `prune-worktrees <root> --all`

## Driving it with verify.sh

Preconditions:

- Fresh fixture. `$V doctor $RUN` is clean.

- **Dead-only report.** Run `$V run $RUN dry-dead -- --no-fetch`. Exit `0`. stdout rows are exactly MERGED `feat-dirty-merged` (DIRTY `yes`), MERGED `feat-merged`, MISSING `feat-missing`, and SQUASHED `feat-squashed`. No ACTIVE, NO_COMMITS, LOCKED, or UNKNOWN rows. stderr ends with `3 repos, 11 linked worktrees, 4 dead (1 dirty) — dry run, pass --remove to delete`.
- **Full report.** Run `$V run $RUN dry-all -- --no-fetch --all`. You get 11 rows, with these REASONs:
  - `feat-active`: `upstream exists, unmerged`
  - `(<sha7>)` detached: `detached HEAD with unmerged commits`
  - `feat-local`: `local-only branch with unmerged commits`
  - `feat-gone`: ACTIVE `upstream exists, unmerged` (no fetch yet)
  - `feat-empty`: NO_COMMITS `no commits beyond origin/main, never pushed`
  - `feat-locked`: LOCKED `worktree is locked`
  - `feat-noremote`: UNKNOWN `no remote default branch found`
  - `feat-squashed`: `changes squash-merged into origin/main`
  - `feat-missing`: `worktree directory no longer exists`
- **No side effects.** In both evidence dirs, `state.diff` is empty.

## Gotchas

- **Known bug (symlinked root):** the PATH column is `os.path.relpath(<git's realpath>, <root as typed>)`. If the root goes through a symlink, rows show junk like `../../../../private/var/...`. Repro: build a fixture, then run `bin/prune-worktrees "$TMPDIR/verify-prune-worktrees/$RUN/root" --no-fetch --all` with the unresolved `$TMPDIR`. The helper sidesteps this by resolving the sandbox path. If you verify a fix, drive it with the unresolved path.
- MISSING detection relies on git's `prunable` flag or a missing dir. A worktree whose dir exists but is broken in some other way is not MISSING.
- `wt/missing` has DIRTY blank because the dirty check is skipped when the dir is gone.
- LOCKED is checked before merge state, so a locked merged worktree is never dead.
- Use `--no-fetch` in this recipe. With fetch, `feat-gone` becomes GONE and the dead count is 5 (see `fetch.md`).
