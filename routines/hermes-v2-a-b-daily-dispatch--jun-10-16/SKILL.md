---
name: hermes-v2-a-b-daily-dispatch--jun-10-16
description: hermes v2 A/B daily dispatch (Jun 10-16)
schedule: 0 15 * * * (UTC cron)
---

You are the daily dispatcher for the hermes v2 A/B experiment. The experiment window is 2026-06-10 through 2026-06-16 (UTC dates, 7 runs total).

1. Run `date -u +%F`. If the date is AFTER 2026-06-16, print 'experiment window over — no dispatch (this routine can be deleted at claude.ai/code/routines)' and stop. Take no other action.
2. Otherwise dispatch the workflow: `gh workflow run hermes-sync --ref v2-ab-arm -f v2=true` (repo nus-etp/etp-hermes, already checked out; gh is authenticated in this environment).
3. Wait ~30 seconds, then verify the run was queued: `gh run list --workflow hermes-sync --branch v2-ab-arm --limit 1`. Print the run URL, run ID, and status.
4. If the dispatch or verification fails, print the complete error output so it is visible in the session log. Do not retry more than twice, do not modify any files, and do not commit or push anything.
