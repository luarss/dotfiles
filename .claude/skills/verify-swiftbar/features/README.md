# prodwatch verification map

This directory is the maintained source for verifying what the SwiftBar `prodwatch` plugin shows. Read the index before driving the plugin, then use the matching feature file as the recipe.

## Baseline preconditions

- `$V doctor $RUN` exits 0.
- `gh` is authenticated as the user whose activity the widget tracks (`PRODWATCH_GITHUB_USER`, or `luarss` by default).
- Each recipe starts from a fresh run-id (an empty sandbox cache) unless it says otherwise.

## Driving conventions

- Drive through `$V run`, `$V check`, and `$V live` only. Pass plugin env through `-- KEY=VAL`.
- Treat menu-bar strings as literal. The title lines start with `<> `, `🐛 `, `$`, and a temperature or `💾`. The dropdown headings are `Work today ·`, `Projects today ·`, `Claude today ·`, `Antigravity today ·`, `GitHub today ·`, `Issues today ·`, `SoC temp ·`, `Disk ·`, and `Battery ·`.
- Never write to `~/.cache/prodwatch` to set up a state. Build the state in the sandbox cache with a run.

## Proof and skip reporting

- Run proof is `stdout.txt` plus `lint.txt`. Number proof is `verdict.txt`. Cache proof is `cache.diff`. Menu-bar proof is `menubar-N.png`.
- Record the run-id and label with every claim.
- A field with no oracle (`temp_avg`, battery) is reported as sanity-checked, not verified.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then has four H2 sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify.sh`, and `Gotchas`.

## Features

- [GitHub activity](./github.md): the `<> N · PR M` title, `GitHub today`, `Issues today`, the local-commit fallback, the cache TTL, and the rate-limit pause.
- [Git commits](./git-commits.md): the `Work today` and `Projects today` sections and their per-repo rows.
- [AI usage](./usage.md): the `$cost · tokens` title and the Claude and Antigravity lines.
- [System health](./system-health.md): the temperature and disk title, `SoC temp`, `Disk`, `Battery`, and the warning flags.
