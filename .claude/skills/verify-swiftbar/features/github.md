# GitHub activity

The first title line shows `<> <contributions> · PR <prs opened today>`, where the contribution count matches today's square on the GitHub profile graph, private repos included. The dropdown repeats this as `GitHub today · N contributions · M PRs` and adds `Issues today · ↑opened · ↓closed` (issues you authored or are assigned to). The second title line `🐛 ↑a/↓b` shows the same issue counts.

## Sub-features

- `gh-contributions`: the title count equals today's contribution-calendar total.
- `gh-prs`: `PR M` equals the PRs you opened since local midnight.
- `gh-issues`: opened and closed counts are the author ∪ assignee union, with duplicates removed.
- `gh-fallback`: with no GitHub data, the title shows the local commit total and drops `· PR`.
- `gh-cache`: a cache younger than `PRODWATCH_GH_TTL` is reused, with no API call.
- `gh-ratelimit`: once `remaining < PRODWATCH_GH_MIN_REMAINING`, fetching pauses until `resetAt`.

## How to get to it (user POV)

- Menu bar title, first and second rotating lines
- Dropdown: `GitHub today` and `Issues today`, plus the `github.com/<user>` link

## Driving it with verify.sh

Preconditions:

- A fresh run-id. `gh auth status` is logged in.

- **Numbers.** Run `$V run $RUN baseline`, then `$V check $RUN baseline`. `contributions`, `prs`, `issues_opened`, and `issues_closed` are `MATCH`. `cache/github-<date>.json` has `contributionDays` with exactly today's date.
- **Fallback.** Run `$V run $RUN fallback -- GH_TOKEN=invalid` in a **new** run-id. The `gh` call fails, so no `github-*.json` is written (`cache.diff` has no github line). The title is `<> <work_commits + projects_commits> | …`, with no `· PR`. There is no `GitHub today` line, and `Issues today · ↑0 opened · ↓0 closed`.
- **Cache reuse.** In the run-id from **Numbers**, run `$V run $RUN reuse` within 300s. `cache.diff` shows no change to `github-*.json`.
- **TTL expiry.** Run `$V run $RUN refetch -- PRODWATCH_GH_TTL=0`. `cache.diff` shows a new mtime for `github-*.json`.
- **Rate-limit pause.** Run `$V run $RUN paused -- PRODWATCH_GH_TTL=0 PRODWATCH_GH_MIN_REMAINING=999999`. The cached `remaining` is below the floor and `resetAt` is in the future, so `cache.diff` shows **no** github change, and the title still shows the cached numbers.
- **Regression check.** `git show 9dc539a:.config/swiftbar/prodwatch.60s.sh > $TMPDIR/old.sh`, then run `PRODWATCH_PLUGIN=$TMPDIR/old.sh $V run sb-old baseline` and `$V check sb-old baseline`. `contributions` shows `0` against the oracle's real count, with `MISMATCH`. This is the bug where the calendar had no `to:` bound.

## Gotchas

- The `contributionsCollection` calendar needs both `from` and `to`. Without `to`, GitHub returns the year starting **tomorrow**, today drops out, and the count falls to 0.
- Contributions are not commits. They include PRs, issues, and reviews, and GitHub counts them a little later than the push. The title can legitimately exceed `Work today`'s commit count.
- `GH_TOKEN=invalid` only overrides the keyring for that one process. It does not log you out.
- `DRIFT` on `prs` or `contributions` just means you did something on GitHub between `run` and `check`. Re-run both to confirm.
- Each fresh run-id costs about 1 GraphQL point for the plugin plus the oracle's REST searches, which have a separate limit of 30 per minute. Don't loop `check` more than about 5 times a minute.
