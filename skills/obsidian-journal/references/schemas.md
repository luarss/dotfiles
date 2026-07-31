# File schemas

Field definitions and file formats for each of the four sections. Each entry is a `.md` file with YAML frontmatter and a markdown body. Each section also has an `Index.md` with a summary table.

---

## Wins

**File path:** `~/work/notes/NUS-Enterprise/Reflections/Wins/YYYY-MM-DD-<slug>.md`

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `type` | Yes | Always `win` |
| `source` | Yes | Always `NUS Enterprise` |
| `date` | Yes | YYYY-MM-DD |
| `status` | Recommended | `Complete` or `Needs-followup` |
| `skills` | Yes | YAML list, e.g. `[Leadership, Technical depth]` |
| `tags` | Yes | Always `[reflections/nus-enterprise, win]` |

### Body fields

| Field | Required | Notes |
|-------|----------|-------|
| `What I did` | Yes | 2–3 sentences, concrete actions |
| `Impact` | Yes | Quantified if possible. Never blank — use "TBD" if unknown |
| `Skills demonstrated` | Yes | From: `Leadership`, `Technical depth`, `Cross-functional`, `Communication`, `Mentorship`, `Strategy`, `Execution`, `Product sense`, `Design` |
| `Evidence` | Recommended | Commit links, PRs, docs, Slack threads |

### Full file format

```
---
type: win
source: NUS Enterprise
date: YYYY-MM-DD
status: Complete
skills: [Skill1, Skill2]
tags: [reflections/nus-enterprise, win]
---

# <Title>

**Date:** YYYY-MM-DD
**Status:** Complete

## What I did
...

## Impact
...

## Skills demonstrated
Skill1, Skill2

## Evidence
- [label](url)
```

### Index.md row format

| Date | Title | Impact | Status |
|------|-------|--------|--------|

New row: `| YYYY-MM-DD | [[YYYY-MM-DD-slug]] | One-line impact summary | Complete |`

---

## Learning

**File path:** `~/work/notes/NUS-Enterprise/Reflections/Learning/YYYY-MM-DD-<slug>.md`

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `type` | Yes | Always `learning` |
| `source` | Yes | Always `NUS Enterprise` |
| `date` | Yes | YYYY-MM-DD |
| `category` | Yes | `Technical`, `Communication`, `Process`, `People`, `Self-management` |
| `tags` | Yes | `[reflections/nus-enterprise, learning, <category-lowercase>]` |

### Body fields

| Field | Required | Notes |
|-------|----------|-------|
| `Situation` | Yes | What happened, briefly |
| `What I learned` | Yes | The insight as a reusable principle |
| `What I'll do differently` | Yes | Concrete behavioral change, not aspiration |

### Full file format

```
---
type: learning
source: NUS Enterprise
date: YYYY-MM-DD
category: Technical
tags: [reflections/nus-enterprise, learning, technical]
---

# <Title>

**Date:** YYYY-MM-DD
**Category:** Technical

## Situation
...

## What I learned
...

## What I'll do differently
...
```

### Index.md row format

| Date | Title | Category |
|------|-------|----------|

New row: `| YYYY-MM-DD | [[YYYY-MM-DD-slug]] | Technical |`

---

## Feedback

**File path:** `~/work/notes/NUS-Enterprise/Reflections/Feedback/YYYY-MM-DD-<slug>.md`

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `type` | Yes | Always `feedback` |
| `source` | Yes | Always `NUS Enterprise` |
| `date` | Yes | YYYY-MM-DD |
| `feedback_source` | Yes | Role + relationship (e.g. "Manager") |
| `feedback_type` | Yes | `Positive`, `Constructive`, `Mixed` |
| `tags` | Yes | Always `[reflections/nus-enterprise, feedback]` |

### Body fields

| Field | Required | Notes |
|-------|----------|-------|
| `Source` | Yes | Role + relationship (e.g. "Manager", "Peer on backend team") |
| `Context` | Yes | What prompted it — 1:1, review, retro, offhand |
| `Feedback` | Yes | Verbatim quote where possible |
| `Type` | Yes | `Positive`, `Constructive`, `Mixed` |
| `My reaction` | Recommended | Initial gut response — separate from the feedback itself |
| `Action taken or planned` | Recommended | What the user is doing with it |

### Full file format

```
---
type: feedback
source: NUS Enterprise
date: YYYY-MM-DD
feedback_source: Manager
feedback_type: Constructive
tags: [reflections/nus-enterprise, feedback]
---

# <Title>

**Date:** YYYY-MM-DD
**Source:** Manager
**Type:** Constructive

## Context
...

## Feedback
"..."

## My reaction
...

## Action taken or planned
...
```

### Index.md row format

| Date | Title | Source | Type |
|------|-------|--------|------|

New row: `| YYYY-MM-DD | [[YYYY-MM-DD-slug]] | Manager | Constructive |`

---

## Discussion

**File path:** `~/work/notes/NUS-Enterprise/Reflections/Discussion/YYYY-MM-DD-<slug>.md`

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `type` | Yes | Always `discussion` |
| `source` | Yes | Always `NUS Enterprise` |
| `date` | Yes | YYYY-MM-DD (date opened) |
| `status` | Yes | `Open`, `Discussed`, `Resolved` |
| `tags` | Yes | Always `[reflections/nus-enterprise, discussion]` |

### Body fields

| Field | Required | Notes |
|-------|----------|-------|
| `Context` | Yes | Why it's on the user's mind |
| `My current thinking` | Recommended | Where the user is on this |
| `Who to discuss with` | Recommended | Manager, mentor, peer, etc. |
| `Status` | Yes | `Open`, `Discussed`, `Resolved` |
| `Outcome` | When resolved | Fill in when Status → Resolved |
| `Date closed` | When resolved | Fill in when Status → Resolved |

### Full file format

```
---
type: discussion
source: NUS Enterprise
date: YYYY-MM-DD
status: Open
tags: [reflections/nus-enterprise, discussion]
---

# <Title>

**Date opened:** YYYY-MM-DD
**Status:** Open

## Context
...

## My current thinking
...

## Who to discuss with
...
```

When resolving, append:

```
## Outcome
...

**Date closed:** YYYY-MM-DD
```

And update the frontmatter `status` to `Resolved`.

### Index.md row format

| Date | Title | Who to discuss with | Status |
|------|-------|---------------------|--------|

New row: `| YYYY-MM-DD | [[YYYY-MM-DD-slug]] | Manager | Open |`

---

## Weekly

The weekly sync note is **not** a Reflections entry. There is **one file per ISO week** (not one per event), living in a different directory, and logging **appends to sections** of that file rather than creating a new file each time.

**Directory:** `~/work/notes/NUS-Enterprise/Weekly/`
**File path:** `~/work/notes/NUS-Enterprise/Weekly/<WEEK>.md` where `<WEEK>` is the ISO week, e.g. `2026-W31`.

### Computing the current week

Run these to derive the identifiers (macOS `date`):

```
WEEK=$(date +%G-W%V)                                  # e.g. 2026-W31 (ISO year + zero-padded ISO week)
MON=$(date -v-mon +%Y-%m-%d)                           # Monday of the current ISO week
WED=$(date -j -v+2d -f %Y-%m-%d "$MON" +%Y-%m-%d)      # Wednesday sync date (Monday + 2)
```

`<WEEK>` names the file; `<WED>` (the Wednesday sync date) fills the frontmatter `date` and the `# Weekly Sync — <WED>` heading. Note the current ISO week can differ from the highest-numbered file on disk (a future week's file may already be scaffolded ahead of time) — `/weekly` targets the **current** ISO week unless the user names a specific week.

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `type` | Yes | Always `weekly-update` |
| `source` | Yes | Always `NUS Enterprise` |
| `week` | Yes | `<WEEK>`, e.g. `2026-W31` |
| `date` | Yes | `<WED>`, the Wednesday sync date |
| `attendees` | Yes | YAML list, default `[]` |
| `facilitator` | Yes | Default blank |
| `tags` | Yes | Always `[updatez/nus-enterprise, weekly]` |

### Full scaffold template

Used only when the current week's file does **not** exist yet. Substitute `<WEEK>` and `<WED>`; keep the HTML comment prompts — they guide later filling.

```
---
type: weekly-update
source: NUS Enterprise
week: <WEEK>
date: <WED>
attendees: []
facilitator: 
tags: [updatez/nus-enterprise, weekly]
---

# Weekly Sync — <WED>

**Attendees:**
**Facilitator:**

---

## TL;DR
<!-- 2–3 bullets, written last; the week's headline. -->
-

## Updates / Status (slides 2 & 3 — two 4-pane project grids, up to 8 cards)
<!-- One H3 per project. Each card = title + status pill + 2–3 bullets. Fill one project at a time. -->

## Todos
### Open
### Done this week

## Adhoc Syncs
<!-- One H3 per sync. Date-prefix so they sort. Use the 1:1 variant for stakeholder conversations. -->

## Seminars / Talks
<!-- Internal or external; talks attended, demos sat in on, vendor pitches. -->

## Blockers / Risks
<!-- Working notes only — no longer its own deck slide. Fold anything live into the
     relevant project card's "current status" / "next step" (name the unblocker). -->
-

## Follow-ups for Next Week
-

## Raw Notes
<!-- unfiltered notes, quotes, links, screenshots -->

---

**Deck:** [[attachments/<WEEK>-deck.pptx]]
```

### Section-append rules

Logging routes the user's item to one section and appends with the **Edit** tool, anchored on the section's heading (or its last existing line). Default the owner to `Shui`.

| Item kind | Section | Line to append |
|-----------|---------|----------------|
| Task to do | `## Todos` → `### Open` | `- [ ] <task> — <owner>` |
| Completed task | `## Todos` → `### Done this week` | `- [x] <task> — <owner>` |
| Project progress | `## Updates / Status` | New `### <Project>  — *<status>*` card with `- Progress since last week:` / `- Current status:` / `- Next steps:` bullets, **or** add/patch a bullet on an existing card |
| Ad-hoc meeting / 1:1 | `## Adhoc Syncs` | `### <WED-or-today> — <Topic> — with <names>` + `- **Context:**` / `- **Discussion:**` / `- **Decisions:**` / `- **Actions:**` |
| Talk / seminar / demo | `## Seminars / Talks` | `### <date> — <Title> — <Speaker> @ <Venue>` + `- **Key takeaways:**` / `- **Relevance to our work:**` / `- **Follow-ups:**` |
| Week headline | `## TL;DR` | `- <bullet>` |
| Risk / blocker | `## Blockers / Risks` | `- <bullet>` |
| Carry-over item | `## Follow-ups for Next Week` | `- <bullet>` |
| Unfiltered note | `## Raw Notes` | `- <bullet>` (or free text) |

When appending under a heading that still holds only the placeholder `-` (empty bullet), replace that placeholder line rather than adding a second empty bullet.

### Index.md row format

`~/work/notes/NUS-Enterprise/Weekly/Index.md` is a **newest-first** table:

| Week | Date | Note / Session |
|------|------|----------------|

Only scaffolding a **new week file** adds a row (appending to sections does not). The new row goes at the **top** of the data rows (immediately below the header separator, above the previously-newest week):

`| <WEEK> | <WED> | [[<WEEK>]] |`

Column padding is cosmetic — approximate the existing alignment; markdown renders regardless.

---

## Index.md update procedure

When adding a new entry:
1. Read `Index.md` to get the current table (exact content needed for `old_str`).
2. Use the **Edit** tool to append a new row, with `old_str` = the last existing row (or the header line if the table is empty / shows `*(No entries yet.)*`), and `new_str` = that row + `\n` + the new row.
3. The title cell must use a wiki link: `[[YYYY-MM-DD-slug]]` (filename without `.md` extension).

Example append for Wins (table has one existing row):
- `old_str`: `| 2026-04-22 | [[2026-04-22-some-win]] | Impact text | Complete |`
- `new_str`: `| 2026-04-22 | [[2026-04-22-some-win]] | Impact text | Complete |\n| 2026-04-24 | [[2026-04-24-new-win]] | New impact | Complete |`

If the table has `*(No entries yet.)*` as a placeholder, replace that line with the header row + new data row.
