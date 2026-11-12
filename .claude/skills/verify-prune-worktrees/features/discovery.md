# Repo discovery

`prune-worktrees` walks the root dir and treats every directory containing a `.git` **directory** as a repo. It stops descending at the first repo it finds, and it skips `node_modules`, `.git`, `.venv`, `venv`, `__pycache__`, `.terraform`, `dist`, `build`, and `.next`. Linked worktrees, which have a `.git` *file*, are not counted as repos. Repos are analyzed in parallel (`--jobs`, default 8).

## Sub-features

- `discover-root` scans the positional `root`, defaulting to `~/work`.
- `discover-skip-dirs` ignores repos under skipped directory names.
- `discover-no-nested` ignores repos nested inside another repo.
- `discover-worktrees-not-repos` keeps linked worktree dirs out of the repo count.
- `discover-jobs` produces identical results with `--jobs 1` and the default.

## How to get to it (user POV)

- `prune-worktrees` (scans `~/work`)
- `prune-worktrees <root>`
- `prune-worktrees <root> --jobs N`

## Driving it with verify.sh

Preconditions:

- A fresh fixture with `node_modules/skipped`, `nested/lib/inner/shadowed`, and `noremote` present, each with a linked worktree under `wt/`.

- **Repo count.** Run `$V run $RUN discover -- --no-fetch --all`. stderr says `3 repos, 11 linked worktrees` (the repos are app, nested/lib, and noremote). No row has BRANCH `feat-skipped` or `feat-shadowed`, even though `wt/skipped` and `wt/shadowed` exist (check `state-before.txt`).
- **Serial run.** Run `$V run $RUN discover-serial -- --no-fetch --all --jobs 1`. `stdout.txt` is byte-identical to `discover/stdout.txt` (`diff` them).
- **Subdirectory root.** Running against a subtree needs the helper's root, so call the binary directly with the sandbox env exported: `GIT_CONFIG_GLOBAL=<sandbox>/gitconfig bin/prune-worktrees "<root>/noremote" --no-fetch --all`. You get `1 repos, 1 linked worktrees`. Save its stdout and stderr next to the other evidence by hand.

## Gotchas

- A repo nested inside another repo (a vendored checkout, or a repo inside a monorepo) is invisible. That's by design, but users sometimes expect it to show up.
- The root itself counts as a repo if it contains `.git/`, and then nothing below it is scanned.
- Submodules have a `.git` file, so they are not discovered as repos.
- Get the sandbox path from `$V paths $RUN`, not by retyping `$TMPDIR` (see the symlink gotcha in `classify.md`).
