---
name: verify-prune-worktrees
description: Drive the real `bin/prune-worktrees` CLI (dotfiles repo) against a disposable git fixture to prove how it classifies worktrees (MERGED/SQUASHED/GONE/MISSING/ACTIVE/NO_COMMITS/LOCKED/UNKNOWN), removes them, fetches, and finds repos. Use this after changing bin/prune-worktrees or when asked to confirm its behavior. Never point it at ~/work.
---

# Verify prune-worktrees

`bin/prune-worktrees` is a Python 3 CLI with no dependencies. It walks a root dir (default `~/work`), finds git repos, and classifies every linked worktree against `<remote>/HEAD`. It is a dry run unless you pass `--remove`. `install.sh` (`install_bin`) symlinks it to `~/.local/bin/prune-worktrees`.

**Isolation rule:** the default root is the user's real `~/work`, and `--remove` / `--delete-branches` destroy real worktrees and branches there. Verification always runs against a sandbox fixture built by the helper. The helper refuses to run unless the root carries its fixture marker. Never run `prune-worktrees` with no root argument, and never pass `--remove` with `~/work` as the root. Each run-id has its own sandbox, so parallel runs never collide.

## Helper

All steps go through one executable script:

```bash
V=/Users/shuisong/work/dotfiles/.claude/skills/verify-prune-worktrees/scripts/verify.sh
RUN=pw-$(date +%Y%m%d-%H%M%S)
$V fixture  $RUN                      # build sandbox
$V doctor   $RUN                      # read-only health check
$V run      $RUN <label> -- <flags>   # run the CLI on the sandbox root, capture evidence
$V paths    $RUN                      # print sandbox/root/evidence paths
$V cleanup  $RUN                      # delete the sandbox, keep evidence
```

The helper exports `GIT_CONFIG_GLOBAL=<sandbox>/gitconfig` and `GIT_CONFIG_NOSYSTEM=1`. That gives a fixed identity, `init.defaultBranch=main`, and no gpg signing, and it keeps the user's global hooks and config out of the run. Set `PRUNE_WORKTREES_BIN=~/.local/bin/prune-worktrees` to exercise the installed symlink instead of the repo file.

## Launch

There is no server. "Launch" means building the fixture:

```bash
$V fixture $RUN
```

You are ready when it prints `fixture ready: <root>` and exits 0. The sandbox lives at `$(cd $TMPDIR && pwd -P)/verify-prune-worktrees/$RUN`, with the path resolved through symlinks (see the path gotcha in `features/classify.md`). Layout:

| Path under `root/` | Repo | Expected status |
|---|---|---|
| `wt/merged` | app, `feat-merged` pushed, then `--no-ff` merged into main | MERGED |
| `wt/dirty-merged` | app, merged, plus an untracked file | MERGED, dirty |
| `wt/squashed` | app, 2 commits squash-merged into main | SQUASHED |
| `wt/gone` | app, pushed, then branch deleted in the bare remote | ACTIVE with `--no-fetch`, GONE after fetch |
| `wt/missing` | app, directory `rm -rf`'d | MISSING |
| `wt/active` | app, pushed, unmerged | ACTIVE "upstream exists" |
| `wt/local` | app, never pushed, unmerged | ACTIVE "local-only" |
| `wt/detached` | app, detached at an unmerged commit | ACTIVE "detached HEAD" |
| `wt/empty` | app, `feat-empty` at an old main commit, never pushed | NO_COMMITS |
| `wt/locked` | app, `git worktree lock` | LOCKED |
| `wt/noremote` | `noremote/` repo with no remote | UNKNOWN |
| `wt/shadowed` | `nested/lib/inner/shadowed`, a repo nested inside the `nested/lib` repo | not listed |
| `wt/skipped` | `node_modules/skipped` | not listed |

The bare remote is at `<sandbox>/remotes/app.git`, outside the scanned root, so `fetch --prune` only touches the local filesystem.

## Doctor

```bash
$V doctor $RUN
```

This is read-only and exits non-zero on any `FAIL`. It checks for python3 >= 3.9 (the script uses `str.removeprefix`), git, that the binary is executable and `--help` parses, that the fixture marker exists, that the root is not `~/work`, that the sandbox gitconfig exists, that app's `origin` is a local directory, and that `origin/HEAD` resolves. It also prints where `~/.local/bin/prune-worktrees` points and the evidence dir. Run it first, and again whenever output looks wrong.

## Drive

```bash
$V run $RUN <label> -- <prune-worktrees flags>
```

This runs `prune-worktrees <sandbox-root> <flags>`. Labels must be unique per run. Most fixture states can only be removed once, so for an independent scenario, build a new run-id instead of reusing a mutated fixture. Feature recipes are in [`features/README.md`](features/README.md).

## Evidence

Each `run` writes the following to `~/.cache/verify-prune-worktrees/<run-id>/<label>/` (override with `VERIFY_PRUNE_EVIDENCE_DIR`):

- `command.txt`: the exact argv
- `stdout.txt`: the table (STATUS, DIRTY, BRANCH, PATH, REASON)
- `stderr.txt`: warnings plus the summary line (`N repos, M linked worktrees, K dead … — dry run`)
- `exit-code.txt`
- `state-before.txt` / `state-after.txt`: `git worktree list --porcelain` and `git branch -a -vv` for every fixture repo, the remote's branches, and `ls wt/`
- `state.diff`: what the run actually changed on disk

Proof standards:

- Go through the real CLI entry point with real flags. Never import the module and call `classify()` directly.
- A claim needs both the table row (what the user sees) and the state diff (the side effect). Example: "removed" in REASON must match a worktree, a `wt/` dir, and (with `--delete-branches`) a branch disappearing in `state.diff`.
- A dry run must show an **empty** `state.diff`. Don't take "dry run" on faith. Note that dry runs still `git fetch --prune` (which updates remote-tracking refs) and write dangling objects through `commit-tree` (the squash probe). Both are expected.

## Cleanup

```bash
$V cleanup $RUN
```

This deletes only `<sandbox base>/<run-id>` and refuses if the fixture marker is missing. Evidence under `~/.cache/verify-prune-worktrees/<run-id>/` is kept, and cleanup prints its path. Run cleanup after failed attempts too. To clear a run-id before rebuilding, run cleanup then fixture again. `fixture` refuses to overwrite an existing sandbox.
