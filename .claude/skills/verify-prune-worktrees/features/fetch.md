# Fetch and remote selection

By default each repo runs `git fetch --prune --quiet <remote>` before classifying, so a branch deleted on the remote shows its upstream as `[gone]`, and an unmerged one becomes GONE. `--no-fetch` skips this. `--remote` picks which remote is used both for fetching and as the default-branch target.

## Sub-features

- `fetch-gone` flips an unmerged branch whose remote branch was deleted from ACTIVE to GONE after fetching.
- `fetch-skip` uses the cached remote-tracking refs with `--no-fetch`, and prints no fetch warnings.
- `fetch-warn` prints `warning: fetch failed in <repo>: ...` on stderr for a repo without the remote. The run still exits 0.
- `fetch-remote` points both fetch and the default-branch lookup at `--remote <name>`.

## How to get to it (user POV)

- `prune-worktrees <root>` (fetches)
- `prune-worktrees <root> --no-fetch`
- `prune-worktrees <root> --remote upstream`

## Driving it with verify.sh

Preconditions:

- A fresh fixture where the bare remote has already lost `feat-gone` but the local `origin/feat-gone` tracking ref still exists. The fixture builds exactly this state.

- **Before fetch.** Run `$V run $RUN nofetch -- --no-fetch --all`. `feat-gone` is ACTIVE `upstream exists, unmerged`. stderr has no `warning:` lines.
- **Fetch.** Run `$V run $RUN fetch -- --all`. `feat-gone` is GONE `upstream origin/feat-gone deleted, unmerged commits`. stderr has `warning: fetch failed in .../nested/lib` and `.../noremote` (`'origin' does not appear to be a git repository`). Exit `0`. stderr says `5 dead`. In `state.diff`, the app branch list changes `[origin/feat-gone]` to `[origin/feat-gone: gone]`, and the worktrees are unchanged.
- **Unknown remote.** Run `$V run $RUN remote-missing -- --all --remote upstream`. 9 rows are UNKNOWN `no remote default branch found`. MISSING and LOCKED keep their status because those checks run before the remote lookup. Every repo prints a fetch warning. Exit `0`.

## Gotchas

- Against `~/work`, the default fetch reaches real network remotes, one per repo, 8 in parallel by default. Credential prompts are disabled (`GIT_TERMINAL_PROMPT=0`), so auth failures show up as warnings, not hangs.
- The fixture's remote is a local path (`doctor` checks this), so fetch stays offline here. Don't add a network remote to the fixture.
- The default branch comes from `refs/remotes/<remote>/HEAD`, falling back to `<remote>/main` and then `<remote>/master`. A clone without `origin/HEAD` and with an unusual default branch name shows UNKNOWN.
- Squash-merged branches whose remote was deleted report SQUASHED, not GONE, because the squash check runs first.
