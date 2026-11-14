# Git commits

The dropdown's `Work today · N commits · +A/-D` and `Projects today · …` headings total today's commits by the tracked identity across the immediate child repos of `~/work` and `~/projects`. Under each heading is one row per active repo (`<repo>  Ncmmt  +A/-D`) linking to the folder, or `— no commits yet today` when there are none.

## Sub-features

- `git-work`: the `~/work` totals use `PRODWATCH_WORK_AUTHOR`.
- `git-projects`: the `~/projects` totals use `PRODWATCH_PROJ_AUTHOR`, which also matches the GitHub noreply address.
- `git-rows`: per-repo rows add up to the heading, and each `href` opens the repo folder.
- `git-empty`: an empty section shows the gray `— no commits yet today` line.

## How to get to it (user POV)

- Dropdown, the `Work today` and `Projects today` sections. Click a row to open the repo in Finder.

## Driving it with verify.sh

Preconditions:

- Any run-id. These numbers don't depend on the cache.

- **Totals.** Run `$V run $RUN baseline`, then `$V check $RUN baseline`. `work_commits`, `work_lines`, `projects_commits`, and `projects_lines` are `MATCH`.
- **Rows add up.** In `stdout.txt`, add up the `Ncmmt` values under `Work today`. The sum equals `work_commits`. Each row's `href=file://$HOME/work/<repo>` exists on disk.
- **Identity.** Run `$V run $RUN other-author -- PRODWATCH_WORK_AUTHOR=nobody@example.invalid`. The output shows `Work today · 0 commits · +0/-0` and `— no commits yet today`.

## Gotchas

- Only `~/work/*/` and `~/projects/*/` with a real `.git` **directory** are scanned. Linked worktrees (where `.git` is a file) and nested repos are skipped, so commits made in a worktree are invisible until merged into a scanned checkout. The oracle uses the same rule, so it can't catch this. Check by hand when a number looks low.
- The plugin sources `~/.config/prodwatch/identity` (office Macs). The oracle does too, so a wrong identity file makes both sides wrong in the same way.
- `--since` is local midnight. Commits with an author date before midnight (rebased or cherry-picked) are counted by author date, not commit date.
