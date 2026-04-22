---
name: claudecode-notion-journal
description: Log structured employment-diary entries to Notion databases via slash commands. Use this skill whenever the user invokes /win, /learning, /feedback, or /discussion — or asks to log, record, or add an entry to their Wins, Learnings, Feedback, or Discussion journal. Also use when the user wants to query, search, or review past diary entries (e.g., "show me my Q2 wins", "what feedback have I gotten about communication"). Triggers on any mention of "employment diary", "work journal", "career log", or the four database names above, even if the slash command syntax isn't used. Requires the Notion MCP server to be available.
---

# Claude Code Notion Journal

A structured journaling skill for an employment diary maintained across four Notion databases: **Wins**, **Learnings**, **Feedback**, and **Discussion**.

The point of this skill is to make the journaling workflow fast enough that the user actually keeps up with it (2–3 minutes per entry), while enforcing enough structure that the entries remain useful for performance reviews, 1:1s, and interviews months later.

## When to invoke

Invoke this skill when the user:

- Uses a slash command: `/win`, `/learning`, `/feedback`, `/discussion`
- Asks to log/record/add something to their diary, journal, or any of the four databases by name
- Asks to query, search, filter, or summarize past entries (e.g. "what wins did I log last quarter?", "pull up the feedback from my skip-level")
- References the diary in passing in a way that implies they want to interact with it ("I should note this as a learning")

If the user's intent is ambiguous between logging and just chatting, ask briefly before routing through the workflow.

## First-time setup

On the first invocation in a session, verify the four databases are reachable before doing anything else:

1. Use the Notion MCP server to search for databases named `Wins`, `Learnings`, `Feedback`, and `Discussion`.
2. Cache the database IDs for the rest of the session.
3. If any are missing, tell the user which ones weren't found and stop — do not try to create them. (The user told us these already exist.) They may need to share the databases with the integration.
4. Verify the schema of each database matches the expected properties in `references/schemas.md`. If properties are missing, tell the user which ones and offer to add them via the MCP before continuing. Don't add them silently.

## The four commands

Each command routes to one database and has a specific structured format. The full property specs live in `references/schemas.md` — read that file before creating any entry so you use the correct property names, types, and select options.

Worked examples of entries (tone, level of detail, how to phrase things) live in `references/examples.md` — consult when the user's input is sparse and you need a template to follow.

### `/win`

For things the user did that mattered. The goal is to capture enough evidence that a future performance review or job interview can be supported by it.

**Required fields:** Date, Title, What I did, Impact, Skills demonstrated
**Recommended:** Evidence (links)

**Follow-up questions to ask** (only the ones not already answered in the user's initial message):

1. "What was the impact? Quantify if you can — time saved, revenue, users affected, stakeholders unblocked."
2. "What skills did this demonstrate?" (offer multi-select from the Skills options in schemas.md)
3. "Any evidence you want to link — PR, doc, Slack thread, dashboard?"

Do not skip the Impact question even if the user resists — this is the single most important field. If they genuinely don't know the impact yet, record "TBD" and add a Status tag of `needs-followup` so they can revisit.

### `/learning`

For insights and behavioral changes. Structured so the user can spot patterns over time (e.g. "most of my learnings are about communication").

**Required fields:** Date, Situation, What I learned, What I'll do differently, Category
**Category options:** Technical, Communication, Process, People, Self-management

**Follow-up questions:**

1. "What's the actual insight — stated as a principle you can reuse?" (If the user gave a situation but no principle, this is the key extraction.)
2. "What will you do differently next time? Be concrete."
3. "Which category?" (single-select from the five above)

The "What I'll do differently" field is where people get vague. Push gently for a concrete behavioral change, not an aspiration. "Communicate better" is not acceptable; "In next week's review, share rough work earlier rather than polishing first" is.

### `/feedback`

For feedback received from others. Capture as close to verbatim as possible because memory distorts.

**Required fields:** Date, Source, Context, Feedback (verbatim), Type
**Recommended:** My reaction, Action taken or planned
**Type options:** Positive, Constructive, Mixed

**Follow-up questions:**

1. "Who gave it and in what context?" (1:1, review, project retro, offhand comment)
2. "What exactly did they say? Try to get as close to their words as you can."
3. "What was your gut reaction?" (This goes in a separate field from the feedback itself — don't merge them. Seeing your initial reaction months later is useful.)
4. "What will you do with it?"

If the feedback is constructive and the user is visibly frustrated about it in how they're describing it, acknowledge that briefly before moving through the questions. Don't lecture them about being open to feedback.

### `/discussion`

For ongoing topics, open questions, and things to raise with the manager. These are longer-lived than the other three — they stay open until resolved.

**Required fields:** Date opened, Topic, Context, Status
**Recommended:** My current thinking, Who to discuss with, Outcome (when closed)
**Status options:** Open, Discussed, Resolved

**Follow-up questions:**

1. "What's the topic or question?"
2. "Why is this on your mind now?"
3. "What's your current thinking?"
4. "Who do you want to discuss this with?"

`/discussion close <topic>` or similar phrasing should update Status to Resolved and prompt for the Outcome field. If the user references an existing open discussion when logging something new, link them (e.g. a win that resolves an open discussion).

## Writing flow

For every entry, regardless of command:

1. **Parse the initial message** — extract whatever fields the user already provided. Don't ask questions they've already answered.
2. **Ask only the missing required fields**, one or two at a time. Never dump all four questions in a wall of text — this is the main reason journaling habits die.
3. **Auto-fill the Date field** to today unless the user specifies otherwise (e.g. "log this as yesterday").
4. **Before writing to Notion, show a preview** of the entry with all fields, and ask "Log this?" The user confirms, edits, or cancels.
5. **On confirmation**, call the Notion MCP to create the page in the correct database with the correct property types (see schemas.md).
6. **On success**, respond with a one-line confirmation and the Notion page URL. Don't re-summarize what was just logged.

## Querying entries

When the user asks to review past entries:

1. Identify which database(s) to query based on the question. "What have I been working on?" → Wins. "Any patterns in my feedback?" → Feedback. Cross-database queries are fine for broader questions.
2. Use the Notion MCP's database query endpoint with filters on Date, Category, Type, Status, or Skills as appropriate.
3. When summarizing multiple entries, group by the most relevant property (category, quarter, source) rather than listing chronologically unless the user asked for chronological.
4. For pattern-detection questions ("am I getting the same feedback repeatedly?"), actually look for patterns — don't just list entries back. Call out themes, frequency, and gaps.

## Principles

- **Low barrier beats completeness.** A 2-minute entry actually written beats a perfect 10-minute entry never written. If the user is rushing, log what they give you and offer to expand later.
- **Structure where it matters, prose where it doesn't.** Properties (Category, Type, Status, Date) enable filtering later. Free-text fields ("What I did", "Feedback") should stay in the user's voice.
- **Don't editorialize.** When logging feedback verbatim, don't soften it. When logging a win, don't inflate it. The entries are more useful later if they're honest now.
- **Quarter/month tagging is automatic.** Derive it from the Date property — don't ask.

## Reference files

- `references/schemas.md` — Exact Notion property definitions for each database. Read before creating or updating entries.
- `references/examples.md` — Worked examples of good entries in each category. Consult when the user's input is sparse or when helping them phrase something.
