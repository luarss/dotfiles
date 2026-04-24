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

## Index.md update procedure

When adding a new entry:
1. Read `Index.md` to get the current table (exact content needed for `old_str`).
2. Use the **Edit** tool to append a new row, with `old_str` = the last existing row (or the header line if the table is empty / shows `*(No entries yet.)*`), and `new_str` = that row + `\n` + the new row.
3. The title cell must use a wiki link: `[[YYYY-MM-DD-slug]]` (filename without `.md` extension).

Example append for Wins (table has one existing row):
- `old_str`: `| 2026-04-22 | [[2026-04-22-some-win]] | Impact text | Complete |`
- `new_str`: `| 2026-04-22 | [[2026-04-22-some-win]] | Impact text | Complete |\n| 2026-04-24 | [[2026-04-24-new-win]] | New impact | Complete |`

If the table has `*(No entries yet.)*` as a placeholder, replace that line with the header row + new data row.
