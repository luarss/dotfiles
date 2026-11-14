# AI usage

The third title line shows today's combined Claude and Antigravity spend and tokens as `$<cost> · <tokens>` (for example `$78.57 · 134.7M`). The dropdown splits these into `Claude today · $x · y tok` and `Antigravity today · $x · y tok`, each followed by a gray `models:` line listing the de-duplicated model names without the `claude-`/`gemini-` prefix or date suffix.

## Sub-features

- `usage-total`: the title cost equals ccusage's daily total.
- `usage-split`: the Claude and Antigravity costs add up to the total.
- `usage-models`: the model lists are de-duplicated and the prefixes are stripped.
- `usage-cache`: ccusage output is cached for 600s, and a response with an unpriced model (tokens but `cost == 0`) is never cached.

## How to get to it (user POV)

- Menu bar title, third rotating line
- Dropdown, the `Claude today` and `Antigravity today` lines

## Driving it with verify.sh

Preconditions:

- A fresh run-id, so ccusage runs live.

- **Total.** Run `$V run $RUN baseline`, then `$V check $RUN baseline`. `cost_total` is `MATCH` or `DRIFT`.
- **Split.** The `Claude today` and `Antigravity today` costs in `stdout.txt` add up to the title cost, within $0.01 of rounding. They also equal `.daily[-1].agents[].totalCost` in `cache/ccusage-<date>.json`.
- **Cache.** Run `$V run $RUN warm` in the same run-id. `duration-seconds.txt` drops from about 45s to about 3s, and `cache.diff` shows no ccusage change.

## Gotchas

- A cold run takes 45–71s (measured 2026-11-14), almost all of it ccusage scanning transcripts. That is at or over SwiftBar's 60s refresh interval, so every time the 600s ccusage TTL expires, a refresh can overlap the next one. A warm run takes about 3s.
- `DRIFT` on cost is normal while any Claude session is active, including the one doing the verifying. ccusage counts your own tokens as you go.
- The live widget's numbers can lag a sandbox run by up to 10 minutes because of `PRODWATCH_CCUSAGE_TTL`.
