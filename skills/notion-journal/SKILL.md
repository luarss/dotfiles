---
name: claudecode-notion-journal
description: Log structured employment-diary entries to Notion via slash commands. Use this skill whenever the user invokes /win, /learning, /feedback, or /discussion — or asks to log, record, or add an entry to their Wins, Learning, Feedback, or Discussion journal. Also use when the user wants to query, search, or review past diary entries (e.g., "show me my Q2 wins", "what feedback have I gotten about communication"). Triggers on any mention of "employment diary", "work journal", "career log", or the four page names above, even if the slash command syntax isn't used. Requires the Notion MCP server to be available.
---

# Claude Code Notion Journal

A structured journaling skill for an employment diary maintained across four Notion pages: **Wins**, **Learning**, **Feedback**, and **Discussion**, all nested under a parent page (e.g. "Nus Enterprise Reflections").

Each section page has:
- A **summary table** at the top — one row per entry, linking to the full entry sub-page
- **Sub-pages** below — one per entry, with fields written as bold markdown labels

The point of this skill is to make the journaling workflow fast enough that the user actually keeps up with it (2–3 minutes per entry), while enforcing enough structure that the entries remain useful for performance reviews, 1:1s, and interviews months later.

## When to invoke

Invoke this skill when the user:

- Uses a slash command: `/win`, `/learning`, `/feedback`, `/discussion`
- Asks to log/record/add something to their diary, journal, or any of the four pages by name
- Asks to query, search, filter, or summarize past entries (e.g. "what wins did I log last quarter?", "pull up the feedback from my skip-level")
- References the diary in passing in a way that implies they want to interact with it ("I should note this as a learning")

If the user's intent is ambiguous between logging and just chatting, ask briefly before routing through the workflow.

## First-time setup

On the first invocation in a session, locate the four section pages:

1. Search Notion for the parent page (e.g. "Nus Enterprise Reflections" or whatever context the user specifies).
2. Fetch the parent page and extract the URLs of the four child pages: **Wins**, **Learning**, **Feedback**, **Discussion**.
3. Cache all five page IDs for the rest of the session.
4. If any child pages are missing, tell the user and stop — do not create them.

No schema validation needed — these are freeform pages, not databases.

## The four commands

Each command routes to one page. Full field specs are in `references/schemas.md`. Worked examples are in `references/examples.md` — consult when the user's input is sparse.

### `/win`

For things the user did that mattered. Goal: enough evidence to support a performance review or job interview.

**Required fields:** Date, Title, What I did, Impact, Skills demonstrated
**Recommended:** Evidence (links), Status

**Follow-up questions** (only for fields not already provided):

1. "What was the impact? Quantify if you can — time saved, revenue, users affected, stakeholders unblocked."
2. "What skills did this demonstrate?" (offer options from schemas.md)
3. "Any evidence to link — PR, commit, doc, Slack thread?"

Never skip Impact. If unknown, record "TBD" and note Status as `Needs-followup`.

### `/learning`

For insights and behavioral changes.

**Required fields:** Date, Title, Situation, What I learned, What I'll do differently, Category
**Category options:** Technical, Communication, Process, People, Self-management

**Follow-up questions:**

1. "What's the actual insight — stated as a reusable principle?"
2. "What will you do differently next time? Be concrete."
3. "Which category?"

Push for a concrete behavioral change in "What I'll do differently", not an aspiration.

### `/feedback`

For feedback received from others. Capture verbatim — memory distorts.

**Required fields:** Date, Title, Source, Context, Feedback (verbatim), Type
**Recommended:** My reaction, Action taken or planned
**Type options:** Positive, Constructive, Mixed

**Follow-up questions:**

1. "Who gave it and in what context?" (1:1, review, retro, offhand)
2. "What exactly did they say? As close to their words as possible."
3. "What was your gut reaction?"
4. "What will you do with it?"

If the feedback is constructive and the user sounds frustrated, acknowledge that briefly before proceeding.

### `/discussion`

For ongoing topics and open questions to raise with the manager.

**Required fields:** Date opened, Title, Context, Status
**Recommended:** My current thinking, Who to discuss with, Outcome (when closed)
**Status options:** Open, Discussed, Resolved

**Follow-up questions:**

1. "What's the topic or question?"
2. "Why is this on your mind now?"
3. "What's your current thinking?"
4. "Who do you want to discuss this with?"

`/discussion close <topic>` → update the sub-page Status to Resolved, prompt for Outcome, and update the summary table row.

## Writing flow

For every new entry:

1. **Parse the initial message** — extract whatever fields the user already provided. Don't re-ask answered questions.
2. **Ask only missing required fields**, one or two at a time.
3. **Auto-fill Date** to today unless the user says otherwise.
4. **Show a preview** of the full entry and ask "Log this?" Wait for confirmation.
5. **On confirmation:**
   a. Create a sub-page inside the relevant section page (e.g. Wins) with the entry content formatted as bold markdown labels (see schemas.md).
   b. Fetch the section page's current summary table.
   c. Append a new row to the table linking to the new sub-page.
6. **On success**, reply with one line: confirmation + sub-page URL.

## Updating an existing entry

When the user asks to edit an existing entry:

1. Fetch the section page to find the sub-page URL from the summary table.
2. Fetch the sub-page to read current content.
3. Show a preview of proposed changes and confirm.
4. Use `update_content` with exact `old_str` / `new_str` to patch the sub-page.
5. If the summary table row also needs updating (e.g. Status changed), patch the section page too.

## Querying entries

1. Fetch the relevant section page(s) to read the summary table for a quick overview.
2. For full content, fetch individual sub-pages by following links from the table.
3. Group results by the most relevant dimension (category, quarter, source) unless the user asked for chronological order.
4. For pattern questions, actually identify themes — don't just list entries.

## Principles

- **Low barrier beats completeness.** A 2-minute entry written beats a perfect entry never written.
- **Structure where it matters, prose where it doesn't.** Field labels enable scanning; free-text stays in the user's voice.
- **Don't editorialize.** Log feedback verbatim. Don't inflate wins.
- **Keep the summary table in sync.** Every new or updated sub-page should be reflected in the table row.

## Reference files

- `references/schemas.md` — Fields, summary table columns, and content format for each section.
- `references/examples.md` — Worked examples of good entries. Consult for tone and level of detail.
