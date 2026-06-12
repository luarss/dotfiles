---
name: daily-notes-review
description: Daily notes review
schedule: 0 9 * * 1-5 (UTC cron)
---

Review the luarss/notes repository and highlight all TODOs.

1. Scan all files in the repository for TODO comments or markers.
2. Extract each TODO with its file path and line number.
3. Organize TODOs by priority or category if patterns emerge (e.g., bugs, features, refactors).
4. Present a summary list with file locations and brief context for each.

If there are no TODOs, confirm briefly.
Post all findings to `luarss-briefing` Slack channel
