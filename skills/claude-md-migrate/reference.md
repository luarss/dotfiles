# Opus 5 / 5.5 migration checklist for CLAUDE.md

Distilled from Anthropic's model-specific prompting guides (fetched 2026-09-23):
- Opus 5: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- Opus 5.5: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5

Scope note: these guides are written for the API. Only the parts that translate to **instruction-file prose** in Claude Code are kept here. API-only mechanics (`max_tokens`, `thinking.display`, `stop_reason` handling, pasted-content tags, time-budget lines, per-message effort) are listed under "Not CLAUDE.md content" so the skill knows to redirect them rather than write them into a CLAUDE.md.

Rule ids: `O5-*` apply to Opus 5 **and** 5.5. `O55-*` apply to Opus 5.5 only.

---

## A. Remove (instructions that now backfire)

### O5-R1 — Explicit verification steps
Remove: "include a final verification step", "use a subagent to verify", "double-check your answer", "re-verify before responding", and harness scaffolding that adds separate verification passes.
Why: Opus 5 verifies and self-corrects without being told; these compound with its own behavior and cause over-verification (wasted tokens, no quality gain).
Keep: concrete, tool-specific checks ("run the tests", "check LSP diagnostics") — those are actions, not generic re-checks.

### O5-R2 — "Only report high-severity" / "be conservative" in review prompts
Rewrite to ask for **everything**, and filter in a separate pass.
Why: Opus 5 review has high precision; a conservative instruction is followed literally and under-reports.

### O5-R3 — "Do not think" / "do not reason" rules
Remove unconditionally.
Why: increases internal-tag leakage on Opus 5 with thinking disabled; meaningless on 5.5 where thinking is always on.

### O5-R4 — Prompt-side vision workarounds
Re-validate any "describe the chart region by region", "zoom into…" style scaffolding. Both models read charts/diagrams/screenshots far better; 5.5 at lowest effort beat Opus 5 at highest. Remove if it no longer earns its keep.

### O55-R5 — "Think carefully / step by step before answering"
Remove for 5.5 (consider removing for 5).
Why: the model decides how much to think; effort is the control. In Anthropic's chat testing, removing this made replies start sooner with no quality drop.

### O55-R6 — "Write out your reasoning in the response"
Remove. Read reasoning from summarized thinking instead.
Why: on 5.5 this can trigger a `reasoning_extraction` safeguard refusal.

### O55-R7 — Thinking-disabled mitigations
The combined "you may say a brief sentence before a tool call / say so if no tool fits / no internal XML tags" instruction was for Opus 5 with thinking **disabled**. On 5.5 thinking can't be disabled — re-test whether it's still needed and drop it if not.

---

## B. Add or strengthen

### O5-A1 — Conciseness (visible response length)
Opus 5 default responses run longer than prior Opus. **Effort does not shorten the visible reply** — prompt for length explicitly.
Guide wording:
> Keep responses focused, brief, and concise. Keep disclaimers and caveats short, and spend most of the response on the main answer. When asked to explain something, give a high-level summary unless an in-depth explanation is specifically requested.

In a long file, add a short reminder near the end:
```
<tone_preference>
Keep outputs reasonably concise.
</tone_preference>
```

### O5-A2 — Progress-update cadence during agentic work
Opus 5 narrates readily (announces every step). 5.5 writes short progress notes between tool calls and is responsive to cadence instructions. Describe the cadence you want; positive examples beat "don't" lists.
Guide wording:
> Before your first tool call, say in one sentence what you're about to do. While working, give a brief update only when you find something important or change direction. When you finish, lead with the outcome: your first sentence should answer "what happened" or "what did you find," with supporting detail after it for readers who want it.

### O5-A3 — Written deliverable length
Files written to disk (reports, docs, summaries) run long. Add:
> Match the length of written documents to what the task needs: cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate.

### O5-A4 — Scope constraint
Opus 5 can expand scope (adds unrequested steps, reinterprets the task). Add:
> Deliver what was asked, at the scope intended. Make routine judgment calls yourself, and check in only when different readings of the request would lead to materially different work. If the request seems mistaken or a better approach exists, say so in a sentence and continue with the task as asked rather than quietly narrowing, widening, or transforming it. Finish the whole task, and stop short of actions that are clearly beyond what was asked.

This also supersedes vaguer "ask one clarifying question when unsure" rules — rewrite those to the "materially different work" threshold so the model doesn't stop for trivia.

### O5-A5 — Subagent delegation guidance
Opus 5 delegates more readily; small tasks get needlessly fanned out. Add:
> Delegate to a subagent only for large tasks that are genuinely independent and parallelizable, such as a wide multi-file investigation. Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work. If one subagent can complete the task, use one rather than several, and keep spawn counts low.

Note: Claude Code injects its own delegation instruction on Opus 5 when using the default `claude_code` system-prompt preset, so in plain Claude Code this is belt-and-braces. It matters more for Agent SDK / custom system prompts. Deterministic caps are harness-level — see section D.

### O5-A6 — Correction narration (optional)
Opus 5 narrates corrections to its earlier statements more than before. If that's noisy:
> Only correct an earlier statement when the error would change the user's code, conclusions, or decisions. State corrections plainly and briefly, then continue the task. For slips that change nothing for the user, make the fix and move on without noting it.

### O55-A7 — Unattended / orchestrated runs only: how turns end
5.5 sometimes ends a turn with a text-only status report while work is still owed. For **fully unattended** agents (cron, OpenClaw/Hermes-style orchestrated sessions), add the guide's "how your turns end" paragraph naming the four unwanted stop types (summary that announces the next step; offer to continue unless told otherwise; list of non-blocking decisions; stopping because a milestone is done) and the wanted ones (nothing can move without the user; the blocker is deliberately protected). It must still defer to confirmation for risky/destructive actions.
**Leave it out of interactive, human-in-the-loop CLAUDE.md files** — there the check-ins are desirable. If one CLAUDE.md serves both, put the paragraph in a separate `@import` that only the unattended profile pulls in. Expect somewhat more tool calls per task.

### O55-A8 — Multi-app / MCP-heavy workflows: explore before acting
Only if the file governs work across several connected apps (mail, docs, sheets, CRM via MCP). 5.5 starts working quickly and can miss context the task didn't point at. Add:
> Before taking any action, explore broadly with tool calls: list and open the emails, documents, spreadsheet tabs and records across the available apps that could be relevant to this task, including ones the task does not explicitly mention, and use what you find.
Costs slightly more tool calls; keep untrusted content out of the searched records.

### O55-A9 — Frontend design defaults
If the file has frontend/style guidance: "avoid a generic AI look" just swaps one default for another. Name **specific** patterns to avoid (e.g. cream/off-white backgrounds, italic accent words in headlines, "01/02/03" section labels, monospace labels, pill buttons) and iterate on what the first result used instead.

---

## C. Do NOT add (tempting but wrong for agentic coding)

### O55-N1 — "Treat earlier answers as settled"
The 5.5 guide's two-sentence "once you have answered something, treat that answer as done…" addition is for **chat products** to cut follow-up-turn latency. The guide says to leave it out of agentic tasks and long analyses, where a later step can reveal an earlier mistake. Don't put it in a coding CLAUDE.md.

### O5-N2 — Any new "always verify / re-check" rule
See O5-R1. Don't reintroduce it under a new name.

---

## D. Not CLAUDE.md content — redirect to harness/settings

- **Effort level.** Main control for thinking (always on in 5.5). Opus 5 defaults `high`; 5.5 defaults `medium`, and 5.5 `medium` ≈ Opus 5 `high`. Names don't map across models — re-sweep on your own tasks instead of carrying the value over. Reserve `xhigh`/`max` for measured gains. Lower effort beats prompt instructions for reducing thinking. Set in the harness (Claude Code effort setting / API `effort`), not in CLAUDE.md prose. Docs: https://platform.claude.com/docs/en/build-with-claude/effort
- **Subagent caps.** `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default 3), `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20), Claude Code ≥ 2.1.217; SDK `max_budget_usd`. **Decision (2026-09-23): keep the defaults** — don't flag their absence. Revisit only if fan-out shows up as a cost/rate-limit problem. If ever set: local sessions read `providers.json` → `overrides.env` or `settings.base.json` (then `./install.sh`); cloud sessions (claude.ai/code, `--cloud`, routines) do **not** read `~/.claude/settings.json` or `~/.claude/CLAUDE.md` — use the cloud environment's variables or the work repo's `.claude/settings.json` `env` (single-repo sessions only).
- **`max_tokens`** (5.5 thinking counts toward it; 128k has worked for long agentic turns), **`thinking.display: "updates"`** for progress notes, **stop_reason handling**, **pasted-content tagging**, **elapsed-time budget lines** — all API/harness, out of scope for an instruction file.
- **Breaking API changes** between Opus 5 → 5.5: https://platform.claude.com/docs/en/models/opus-5-5/migration-guide

---

## E. Behavioural summary (for the "why" column)

| Area | Opus 5 (vs 4.8) | Opus 5.5 (vs 5) |
|---|---|---|
| Default effort | `high` | `medium` (≈ Opus 5 `high`) |
| Thinking | on by default; can disable at ≤ `high` | always on |
| Visible verbosity | longer; prompt for brevity | fewer tokens, 30%+ faster; still prompt |
| Narration | announces steps; tune with cadence | short progress notes between tool calls |
| Verification | self-verifies; remove explicit steps | same |
| Scope | may widen; constrain | gets to work quickly; may under-explore in multi-app tasks |
| Subagents | delegates readily; guide/cap | sustains long parallel runs; time-aware |
| Early stop | — | may end turn with text report; unattended harnesses need the turn-ending paragraph |
| Vision | much better; drop workarounds | better still, even at low effort |
| Safeguards | — | new bio + `reasoning_extraction` classifiers; vuln-finding in code allowed |
