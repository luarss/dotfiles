---
description: Mirror remote claude.ai routines (scheduled cloud agents) into routines/
---

Remote routines live server-side at claude.ai and are only reachable through the
`RemoteTrigger` tool (in-process OAuth — curl cannot authenticate). Sync them into
this repo as follows:

1. Load the tool: `ToolSearch` with query `select:RemoteTrigger`, then call
   `RemoteTrigger {action: "list"}`.
2. For each routine in `.data[]`, derive its slug: lowercase the `name`, replace
   every character outside `[a-z0-9]` with `-`, trim leading/trailing `-`.
3. Write `routines/<slug>/SKILL.md` in exactly this shape (prompt taken verbatim
   from `.job_config.ccr.events[0].data.message.content`; schedule from
   `.cron_expression` or `.run_once_at`):

   ```
   ---
   name: <slug>
   description: <routine name verbatim>
   schedule: <cron expr> (UTC cron)        # or: once at <run_once_at>
   ---

   <prompt>
   ```

   This repo is PUBLIC — write nothing else. No `routine.json`, no trigger /
   environment / connector / account IDs.
4. Delete any `routines/<slug>/` directory whose slug is no longer in the server
   list — it was deleted or renamed at claude.ai (git history keeps the old copy).
5. Re-run `./install.sh` (refreshes and prunes the `~/.claude/scheduled-tasks`
   symlinks on the work machine), run `bats tests/install.bats`, then show
   `git status` for review. Do not commit unless asked.
