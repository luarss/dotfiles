---
name: claude-ai-org-skill-sync
description: claude-ai-org-skill-sync
schedule: 0 1 * * * (UTC cron)
---

You are the daily sync checker for skills provisioned to the claude.ai organization from the nus-etp/skills repo. The repo is already cloned for you.

1. Read claude-ai-manifest.json at the repo root. Ignore the `_comment` key. Every other key is a skill directory name provisioned to the claude.ai org; its value is the commit sha whose content was last packaged (null = never packaged).

2. For each skill, get the latest commit touching its directory: `git log -1 --format=%H -- "<skill>/"`. Collect skills whose latest sha differs from the manifest value (null always counts as differing).

3. If NO skill differs: end the session immediately. Do not commit anything, do not send any Slack message.

4. For each changed skill:
   - Run the validator first: `pip install pyyaml 2>/dev/null; python3 scripts/validate_skills.py`. If validation fails for that skill, do NOT package it; report the failure in the Slack DM instead.
   - Run `scripts/package_claude_ai.sh <skill>` (it builds dist/<skill>.zip, automatically swapping in the skill's SKILL.claude-ai.md web variant if one exists).

5. Update claude-ai-manifest.json with the new sha for each successfully packaged skill, then commit and push to main: `git add claude-ai-manifest.json && git add -f dist/<skill>.zip ... && git commit -m "chore: rebuild claude.ai skill package(s): <names>" && git push origin main` (dist/ is gitignored, hence -f). Never modify any skill's content files - you only touch the manifest and dist/*.zip.

6. Send a SHORT Slack DM to the user Song Luar (find them with the Slack user-search tool; email song.luar@a5x.ai). Include: which skill(s) changed and were repackaged, a download link per zip (https://github.com/nus-etp/skills/raw/main/dist/<skill>.zip), and the reminder that an org admin must replace each skill in claude.ai under Organization settings > Skills (remove the old entry, then + Add the new zip - there is no API for this). If any validation or push failed, say so in the same DM.

Edge cases: if the push is rejected (e.g. branch protection or a race), retry once with `git pull --rebase origin main` first; if it still fails, send the DM anyway and mention the push failure so the user can intervene.
