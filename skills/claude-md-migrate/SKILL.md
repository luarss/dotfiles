---
name: claude-md-migrate
description: Audit and rewrite CLAUDE.md / AGENTS.md instruction files for Claude Opus 5 or Opus 5.5, based on Anthropic's model-specific prompting guides. Use for /claude-md-migrate, or any ask to migrate, update, tune, or review a CLAUDE.md for a new Claude model.
argument-hint: "[opus-5|opus-5.5] [path ...] [--apply] [--dry-run]"
disable-model-invocation: true
---

# /claude-md-migrate — Tune CLAUDE.md for Opus 5 / 5.5

Audit one or more Claude Code instruction files (`CLAUDE.md`, `AGENTS.md`, and anything they `@import`) against the behavioral changes documented in Anthropic's prompting guides, then propose and apply edits. The rules live in `reference.md` next to this file — **read it first, every time**; do not work from memory.

Sources (re-fetch if the user asks for the latest, otherwise trust `reference.md`):
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5

## Arguments

- **Model**: `opus-5` or `opus-5.5`. Default `opus-5.5`. The 5.5 guide says Opus 5 patterns remain a valid starting point, so `opus-5.5` applies **both** checklists; `opus-5` applies only the Opus 5 one.
- **Paths**: files to audit. If none given, audit the defaults below.
- `--dry-run`: report only, never edit.
- `--apply`: skip the confirmation step and apply the proposed edits directly.

## Default targets

1. `~/.claude/CLAUDE.md` and every file it `@imports` (e.g. `~/.claude/AGENTS.md`).
2. In the current repo: `./CLAUDE.md`, `./AGENTS.md`, `./.claude/CLAUDE.md`, and their imports.

**Resolve symlinks before editing.** In this dotfiles setup `~/.claude/AGENTS.md` is a symlink into `~/work/dotfiles/.claude/AGENTS.md`, and `~/.claude/CLAUDE.md` is *generated* by `install.sh` (it just holds `@AGENTS.md` / `@RTK.md`). Edit the repo source (`readlink -f`), never the generated file. Skip files that are only `@import` lines.

## Workflow

1. **Read `reference.md`**, then read every target file in full.
2. **Classify each instruction** in the file as one of:
   - **Model-behavior prose** — how to communicate, verify, scope, think, delegate. This is what the checklist targets.
   - **Concrete tool/harness rules** — LSP usage, RTK, hook descriptions, security guards, deny lists, repo layout, commands. **Leave these alone** even if they superficially look like "verification" (e.g. "check LSP diagnostics after editing" is a concrete action, not a generic re-check).
3. **Audit** the model-behavior prose against every rule in `reference.md`. For each hit record: file, line, the offending or missing text, the rule id, and the action (`remove`, `rewrite`, `add`, `keep`). Also record rules that explicitly say **do not add** if the file is about to get them (e.g. the 5.5 "treat earlier answers as settled" line is wrong for agentic coding).
4. **Draft edits.** Prefer the guide's own wording (quoted in `reference.md`) adapted to the user's voice and existing section structure. Consolidate: one conciseness block, one scope block, one delegation block, one progress-update block — don't sprinkle. In a long file, add the short `<tone_preference>` reminder near the end. Keep the user's Conventional-Commits, code-style, and dependency-pinning rules untouched.
5. **Report** before touching anything:
   - A table: `line | current text (trimmed) | rule | action | why` — one row per finding.
   - A list of harness-level items that belong in `settings.json`/env rather than CLAUDE.md (effort level, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`). In this repo those go in `providers.json` `overrides.env` or `settings.base.json`, then `./install.sh`. Suggest, don't edit them from this skill.
   - The proposed unified diff per file.
6. **Confirm once** ("apply these edits?") unless `--apply` or `--dry-run` was passed. Then apply with minimal edits — no reflowing or reordering of untouched sections.
7. **Verify**: re-read the edited file, check `@import` lines still resolve, and if a generated `CLAUDE.md` is involved remind the user to re-run `./install.sh` and restart Claude Code.

## Guardrails

- Never edit security-related content (deny lists, hook descriptions, guard behavior).
- Never drop an instruction whose purpose you can't map to a checklist rule — flag it as `keep` with a note instead.
- Don't invent behavioral claims about the model. If a finding isn't backed by a rule in `reference.md`, don't make it.
- Deliverable length: the audit table should fit on one screen per file. Findings, not essays.
