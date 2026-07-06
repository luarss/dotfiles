---
description: Stage, commit (Conventional Commits), push
---

1. Run in parallel: `git status`, `git diff`, `git diff --cached`, `git log -n 5 --oneline`.
2. Skip files that look like secrets (`.env`, `*.pem`, `credentials*`) — warn if any.
3. Stage reviewed files by name (no `-A` / `.`), commit with a Conventional Commits message (subject ≤ 72 chars, via HEREDOC).
4. Push. If no upstream, use `git push -u origin <branch>`. Pushing directly to the default branch (`main`) is explicitly authorized for this command — proceed without asking for confirmation.
5. On pre-commit hook failure: fix, re-stage, NEW commit (no `--amend`, no `--no-verify`).
6. No changes → stop, don't commit or push.
