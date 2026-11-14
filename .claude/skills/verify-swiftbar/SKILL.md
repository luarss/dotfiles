---
name: verify-swiftbar
description: Drive the real SwiftBar `prodwatch` plugin (dotfiles repo, `.config/swiftbar/prodwatch.60s.sh`) against live GitHub, ccusage, git, and disk sources, and prove every number in the menu bar title and dropdown against an independent oracle. Also refreshes the plugin inside the running SwiftBar app and screenshots the menu bar. Use after changing prodwatch, or when the user says a SwiftBar number looks wrong.
---

# Verify SwiftBar prodwatch

`prodwatch.60s.sh` is a SwiftBar plugin. SwiftBar runs it every 60s and renders its stdout. The lines before the first `---` rotate in the menu bar about every 5s. Everything after that is the dropdown. `install.sh` (`install_swiftbar`, work and office machines only) symlinks it into `~/.config/swiftbar/` and points SwiftBar's `PluginDirectory` there.

The plugin reads real data: one GitHub GraphQL call (cached for `PRODWATCH_GH_TTL`, 300s), `ccusage` (cached for 600s), `git log` over `~/work/*` and `~/projects/*`, IOKit die temperatures, `df`/`diskutil`, and `ioreg` battery data. `tests/prodwatch.bats` stubs all of these. This skill does the opposite: it runs the real plugin against real sources and checks what it prints.

**Isolation rule:** `run` points `PRODWATCH_CACHE_DIR` at a per-run sandbox, so the plugin never reads or writes `~/.cache/prodwatch`, the cache the live SwiftBar instance uses. A sandbox starts empty, so the first run always makes real GitHub and ccusage calls. Only `live` touches the user's real SwiftBar, and it only asks SwiftBar to refresh (a read-only URL-scheme call).

## Helper

All steps go through one executable script:

```bash
V=/Users/shuisong/work/dotfiles/.claude/skills/verify-swiftbar/scripts/verify.sh
RUN=sb-$(date +%Y%m%d-%H%M%S)
$V doctor  $RUN                          # read-only health check
$V run     $RUN <label> [-- KEY=VAL ...] # run the plugin, capture and lint the output
$V check   $RUN <label>                  # compare the run's numbers with independent oracles
$V live    $RUN <label> [frames]         # refresh inside SwiftBar, screenshot the menu bar
$V paths   $RUN                          # print sandbox/cache/evidence paths
$V cleanup $RUN                          # delete the sandbox, keep evidence
```

`KEY=VAL` pairs after `--` are passed to the plugin as env vars, for example `PRODWATCH_GH_TTL=0`. Set `PRODWATCH_PLUGIN=<file>` on the helper to run a different copy of the plugin, such as a `git show <rev>:.config/swiftbar/prodwatch.60s.sh` export, to prove a regression. Labels are unique within a run-id. The sandbox cache persists across labels in the same run-id, so a second label sees the first one's cache.

## Launch

There is no server. Each `run` is one complete plugin invocation, as SwiftBar would make it. You are ready when `doctor` exits 0. To get a cold cache, use a new run-id. To get a warm one, add another label to the same run-id.

## Doctor

```bash
$V doctor $RUN
```

This is read-only and exits non-zero on any `FAIL`. It checks for macOS, `git`/`jq`/`node`/`python3`/`ccusage`/`gh`, `gh auth`, that the plugin is executable and passes `bash -n`, and that the sandbox doesn't overlap the real cache. It also prints the GraphQL rate budget. It `WARN`s, but does not fail, when SwiftBar isn't running, when `PluginDirectory` isn't `~/.config/swiftbar`, or when the installed plugin isn't a symlink to this repo. In that last case `live` would show a different file than `run` tested.

## Drive

```bash
$V run   $RUN baseline
$V check $RUN baseline
```

`run` prints the plugin's stdout, then `exit=… duration=…s lint: titles=N problems=M`. It exits non-zero if the plugin failed or the lint found problems. The lint enforces SwiftBar's line format: every non-`---` line has `text | params`, params are only `font size color href refresh`, there is at least one title line, and every title line shows a number.

`check` parses the output and recomputes each value from a separate source, through a different API or code path than the plugin uses:

| Field | Oracle |
|---|---|
| `contributions` | GraphQL `contributionsCollection(from: midnight, to: now)` for today's date |
| `prs` | REST search `gh search prs --author=@me --created=>=midnight` |
| `issues_opened` / `issues_closed` | `gh search issues`, author ∪ assignee, unique URLs |
| `cost_total` | `ccusage daily --json` without `--by-agent` |
| `work_*` / `projects_*` | `git log --shortstat` over the same repos and author regex (the plugin uses `--numstat`) |
| `disk_free_percent` | `df -k /System/Volumes/Data` |
| `temp_avg` | sanity range 20–110°C (no second sensor reader) |

Verdicts: `MATCH`; `DRIFT` (the oracle is slightly higher on a counter that only grows, because `check` runs after `run`); `DRIFT?` (line totals differ, so re-run to confirm); `SANE`; `SKIP` (both values empty); `MISMATCH` and `MISSING` (both count as failures). `check` exits non-zero on any failure. Feature recipes are in [`features/README.md`](features/README.md).

## Live SwiftBar

```bash
$V live $RUN live 4
```

This opens `swiftbar://refreshplugin?name=prodwatch`, waits 3s, and then takes `frames` full-screen captures 5s apart (`screen-N.png`) plus an 80px menu-bar crop of each (`menubar-N.png`). It runs the installed plugin once more to write `expected-titles.txt`. Each crop should show one of those title lines, because they rotate. Read the `menubar-*.png` files to compare. This uses the real cache, so its numbers can be up to 5 or 10 minutes older than a sandbox `run`. A fullscreen app hides the menu bar, so a crop can show app content instead. Treat such a frame as unusable, not as a failure, and ask the user to leave a normal desktop in front before re-running. The terminal needs Screen Recording permission. Without it, the captures show only the wallpaper.

## Evidence

Everything goes under `~/.cache/verify-swiftbar/<run-id>/<label>/` (override with `VERIFY_SWIFTBAR_EVIDENCE_DIR`):

- `run`: `command.txt`, `stdout.txt`, `stderr.txt`, `exit-code.txt`, `duration-seconds.txt`, `ran-at.txt`, `lint.txt`, `cache/` (copies of the GitHub and ccusage JSON the plugin used), `cache-before.txt`/`cache-after.txt`/`cache.diff` (sandbox cache), and `real-cache-*.txt`/`real-cache.diff`
- `check`: `shown.tsv`, `expected.tsv`, `verdict.txt`, `checked-at.txt`
- `live`: `screen-N.png`, `menubar-N.png`, `expected-titles.txt`, `real-cache.diff`

Proof standards:

- Run the real plugin file through bash, the way SwiftBar does. Never source it, and never stub a source in this skill. Stubbing is what the bats suite is for.
- A number is proven when `check` gives `MATCH` (or `DRIFT` with a plausible gap) and the backing JSON in `cache/` agrees.
- For cache behavior, prove it from `cache.diff`: a fetch changes the mtime, a reuse leaves it unchanged. Don't trust the TTL variables.
- `real-cache.diff` should be empty for `run`. A change there usually comes from SwiftBar's own 60s refresh, which happens alongside the run. Confirm by comparing the mtime with `ran-at.txt`. A change that SwiftBar's refresh can't explain means the plugin ignored `PRODWATCH_CACHE_DIR`.

## Cleanup

```bash
$V cleanup $RUN
```

This deletes only `$TMPDIR/verify-swiftbar/<run-id>` and refuses if the sandbox marker is missing. Evidence is kept, and cleanup prints its path. `live` starts no processes, so it has nothing to tear down.
