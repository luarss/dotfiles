---
name: merge-pr
description: Squash-merge a PR, delete its branches and worktree, fast-forward main, record the merge in the wiki.
argument-hint: "[PR number or branch]"
disable-model-invocation: true
---

1. Run `~/.claude/skills/merge-pr/merge-pr.sh $ARGUMENTS` from the repo. On `ABORT:` report it and stop. `note=` lines are things it skipped.
2. If it printed `wiki=<dir>`: `git -C <dir> pull --ff-only`; `grep -rn "#<pr>" <dir>/wiki/`. If found, amend in place to note `merged \`<short-sha>\``; else append to `wiki/log.md` as `## [YYYY-MM-DD] <action> | <title> (<repo> [#<pr>](<url>))` with facts from the PR only. Commit `log: <repo> #<pr> merged (<short-sha>)` and push.
3. If it printed `milestone=<pr|commit>:<n>` (every 100th PR number or commit on base, 1000ths included), write one original haiku (5-7-5, concrete imagery from this PR's title and change, no clichés; grander for a 1000th) celebrating it. Put it in the wiki entry from step 2 as a blockquote under the line, if one was written.
4. Reply in one line: sha, worktree removed, wiki commit, notes. If the session cwd was the removed worktree, say `cd` to main. Then, for a milestone, name it (e.g. `🎉 PR #500`) and give the haiku on its own three lines.
