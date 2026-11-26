# prune-worktrees verification map

This directory is the maintained source for verifying what `bin/prune-worktrees` does for a user. Read this index first, then use the matching feature file as the recipe.

## Baseline preconditions

- `V=/Users/shuisong/work/dotfiles/.claude/skills/verify-prune-worktrees/scripts/verify.sh`, plus a fresh `RUN` id.
- `$V fixture $RUN` succeeded and `$V doctor $RUN` shows no `FAIL`.
- The fixture is unmutated: no `--remove` run yet on this run-id, unless a recipe says otherwise.
- Never drive `~/work` or any root the helper did not build.

## Driving conventions

- Every invocation goes through `$V run $RUN <label> -- <flags>`, which supplies the sandbox root as the positional `root`.
- Assert on the STATUS and BRANCH columns and the exact REASON text, not column offsets. The table width depends on content.
- The summary line goes to **stderr**. Rows go to stdout.
- A mutating recipe (`--remove`) uses up the fixture. Start a new run-id for the next independent mutating scenario.

## Proof and skip reporting

- Cite the evidence dir `~/.cache/verify-prune-worktrees/<run>/<label>/` for every claim.
- Mutation proof = the REASON action text (`removed`, `pruned`, `branch deleted`, `skipped: dirty`) plus the matching lines in `state.diff`.
- Dry-run proof includes an empty `state.diff`.
- `gh` proof is `gh-calls.txt` in the evidence dir: one line per stub call (`<cwd> <argv>`). It is empty when `--no-gh` is passed.
- If a fixture state a recipe needs is missing, report the failure and the unmet precondition. Don't edit the recipe to make it pass.

## Feature entry contract

Each feature file has an H1, a one-paragraph description, and then exactly four H2s: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify.sh`, `Gotchas`.

## Features

- [Classify worktrees](./classify.md): the dry-run report, every status, `--all`, the dirty flag, and the summary line.
- [Merged pull requests](./pull-requests.md): the `gh` lookup that marks a branch MERGED when its PR merged into any base, the local-commits guard, and `--no-gh`.
- [Remove dead worktrees](./remove.md): `--remove`, the dirty skip, `--force`, and `--delete-branches`.
- [Fetch and remote selection](./fetch.md): `fetch --prune` turning ACTIVE into GONE, `--no-fetch`, `--remote`, and fetch warnings.
- [Repo discovery](./discovery.md): the root argument, skipped dirs, nested repos, and `--jobs`.
