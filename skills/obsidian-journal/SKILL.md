---
name: claudecode-obsidian-journal
description: Log and query employment-diary entries (Wins, Learning, Feedback, Discussion) in Obsidian. Use for /win, /learning, /feedback, /discussion, or any ask to log, record, search, or review entries in the diary, work journal, or career log.
---

# Claude Code Obsidian Journal

A structured journaling skill for an employment diary maintained in Obsidian across four sections: **Wins**, **Learning**, **Feedback**, and **Discussion**, all under `~/work/notes/NUS-Enterprise/Reflections/`.

Each section has:
- An **`Index.md`** — summary table at the top, one row per entry, linking to the entry file via Obsidian wiki link
- **Entry files** — one `.md` file per entry, named `YYYY-MM-DD-<slug>.md`, with YAML frontmatter and a markdown body

The point of this skill is to make the journaling workflow fast enough that the user actually keeps up with it (2–3 minutes per entry), while enforcing enough structure that the entries remain useful for performance reviews, 1:1s, and interviews months later.

## When to invoke

Invoke this skill when the user:

- Uses a slash command: `/win`, `/learning`, `/feedback`, `/discussion`
- Asks to log/record/add something to their diary, journal, or any of the four sections by name
- Asks to query, search, filter, or summarize past entries (e.g. "what wins did I log last quarter?", "pull up the feedback from my skip-level")
- References the diary in passing in a way that implies they want to interact with it ("I should note this as a learning")

If the user's intent is ambiguous between logging and just chatting, ask briefly before routing through the workflow.

## Setup

On the first invocation, verify the four section directories exist:

- `~/work/notes/NUS-Enterprise/Reflections/Wins/`
- `~/work/notes/NUS-Enterprise/Reflections/Learning/`
- `~/work/notes/NUS-Enterprise/Reflections/Feedback/`
- `~/work/notes/NUS-Enterprise/Reflections/Discussion/`

If any are missing, tell the user and stop. No caching needed — paths are static for the session.

## The four commands

Each command routes to one section. Full field specs are in `references/schemas.md`. Worked examples are in `references/examples.md` — consult when the user's input is sparse.

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

`/discussion close <topic>` → update the entry file Status to Resolved, prompt for Outcome, and update the Index.md row.

## Writing flow

For every new entry:

1. **Parse the initial message** — extract whatever fields the user already provided. Don't re-ask answered questions.
2. **Ask only missing required fields**, one or two at a time.
3. **Auto-fill Date** to today unless the user says otherwise.
4. **Generate slug** from the title: lowercase, spaces → hyphens, strip non-`[a-z0-9-]` characters, max ~60 chars.
5. **Show a preview** of the full file (frontmatter + body, as it will be written to disk) and ask "Log this?" Wait for confirmation.
6. **On confirmation:**
   a. **Write** the new file: `~/work/notes/NUS-Enterprise/Reflections/<Section>/YYYY-MM-DD-<slug>.md`
   b. **Read** the section's `Index.md` to get the current table content.
   c. **Edit** `Index.md` to append a new row (use the existing last row as `old_str`, append the new row to `new_str`). Title cell uses a wiki link: `[[YYYY-MM-DD-<slug>]]`.
7. **On success**, reply with one line: confirmation + the relative file path (from `~/work/notes/`).

## Updating an existing entry

When the user asks to edit an existing entry:

1. Read `Index.md` to find the filename from the wiki link, or list the section directory.
2. Read the entry file to see current content.
3. Show a preview of proposed changes and confirm.
4. Use the **Edit** tool to patch the file with exact `old_str` / `new_str`.
5. If the Index.md row also needs updating (e.g. Status changed), patch `Index.md` too.

## Querying entries

1. Read the relevant section's `Index.md` for a quick overview of all entries.
2. For full content, Read individual entry files as needed.
3. Group results by the most relevant dimension (category, quarter, source) unless the user asked for chronological order.
4. For pattern questions, actually identify themes — don't just list entries.

## Principles

- **Low barrier beats completeness.** A 2-minute entry written beats a perfect entry never written.
- **Structure where it matters, prose where it doesn't.** Field labels enable scanning; free-text stays in the user's voice.
- **Don't editorialize.** Log feedback verbatim. Don't inflate wins.
- **Keep Index.md in sync.** Every new or updated entry should be reflected in the table row.

## Reference files

- `references/schemas.md` — Frontmatter fields, body format, and Index.md row format for each reflection section.
- `references/examples.md` — Worked examples of good entries. Consult for tone and level of detail.
