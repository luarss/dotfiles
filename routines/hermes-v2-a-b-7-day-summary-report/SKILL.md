---
name: hermes-v2-a-b-7-day-summary-report
description: hermes v2 A/B 7-day summary report
schedule: once at 2026-06-17T00:00:00Z
---

You are writing the 7-day summary report for the hermes v2 A/B experiment (window: 2026-06-10 through 2026-06-16). The repo nus-etp/etp-hermes is checked out.

Setup: `git fetch origin v2-ab-arm && git checkout v2-ab-arm && git pull`.

Context to read first:
- The 'v2 A/B arm' section of CLAUDE.md (explains the experiment design and the decision rule).
- `signals/ab/metrics.jsonl` (one row per compared day) and `signals/ab/report.md` (history table + latest disagreements).
- The daily outputs under `signals/updates/`, `signals/agent/`, `signals/v2/updates/`, `signals/v2/agent/` for the window dates, plus git log of `signals/ab/report.md` to recover each day's disagreement lists (report.md is rewritten daily, so use `git log -p -- signals/ab/report.md` to see all 7 days, not just the last).

Write `signals/ab/SUMMARY-7day.md` containing:
1. A per-day table: date, v1 items, v2 items, overlap, v1-only, v2-only, jaccard (from metrics.jsonl), plus a totals row.
2. Every v2-only item across the window, each categorized by your judgment after reading the item: real signal / same-name different entity / stale (outside the layer's date window) / source-policy concern (e.g. Google News RSS items, which production intentionally avoids as a feed class) / low-content. Briefly justify each call.
3. Every v1-only item (candidate v2 misses), same treatment.
4. Anomalies worth flagging (e.g. days where one arm errored, items v1 dropped despite the pre_extracted auto-keep policy, dispatch failures visible as missing dates).
5. A verdict paragraph applying CLAUDE.md's decision rule: recommend one of (a) promote v2's judgment sections into the production prompts, (b) iterate on the v2 prompts and extend the experiment, or (c) extend the window unchanged because evidence is insufficient. Be explicit that 7 days is below the ~16-day full gap-fill rotation, so a 'promote' verdict needs strongly lopsided evidence.

Then commit ONLY that file with message `docs(ab): 7-day v2 A/B summary (2026-06-10 to 2026-06-16)` and push to v2-ab-arm. If the push is rejected (non-fast-forward), pull --rebase and push again. Do not modify any other file. If signals/ab/ data is missing or covers fewer than 5 of the 7 dates, still write the summary with what exists and say prominently which dates are missing.
