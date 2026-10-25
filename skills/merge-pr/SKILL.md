---
name: merge-pr
description: Squash-merge a PR, delete its branches and worktree, fast-forward main, record the merge in the wiki.
argument-hint: "[PR number or branch]"
disable-model-invocation: true
---

1. Run `~/.claude/skills/merge-pr/merge-pr.sh $ARGUMENTS` from the repo. On `ABORT:` report it and stop. `note=` lines are things it skipped.
2. If it printed `wiki=<dir>`: `git -C <dir> pull --ff-only`; `grep -rn "#<pr>" <dir>/wiki/`. If found, amend in place to note `merged \`<short-sha>\``; else append to `wiki/log.md` as `## [YYYY-MM-DD] <action> | <title> (<repo> [#<pr>](<url>))` with facts from the PR only. Commit `log: <repo> #<pr> merged (<short-sha>)` and push.
3. Reply in one line: sha, worktree removed, wiki commit, notes. If the session cwd was the removed worktree, say `cd` to main.
