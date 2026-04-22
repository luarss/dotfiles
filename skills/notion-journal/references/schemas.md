# Page schemas

Field definitions for each of the four section pages. Entries are sub-pages with fields written as bold markdown labels. Each section page also has a summary table at the top.

---

## Wins

### Summary table columns

| Date | Title | Impact | Status |
|------|-------|--------|--------|

### Sub-page fields

| Field | Required | Notes |
|-------|----------|-------|
| `Date` | Yes | Default to today (YYYY-MM-DD) |
| `What I did` | Yes | 2–3 sentences, concrete actions |
| `Impact` | Yes | Quantified if possible. Never blank — use "TBD" if unknown |
| `Skills demonstrated` | Yes | From: `Leadership`, `Technical depth`, `Cross-functional`, `Communication`, `Mentorship`, `Strategy`, `Execution`, `Product sense`, `Design` |
| `Evidence` | Recommended | Commit links, PRs, docs, Slack threads |
| `Status` | Recommended | `Complete` or `Needs-followup` |

### Sub-page content format

```
**Date:** YYYY-MM-DD

**What I did:** ...

**Impact:** ...

**Skills demonstrated:** Skill1, Skill2

**Evidence:** [label](url), [label](url)

**Status:** Complete
```

---

## Learning

### Summary table columns

| Date | Title | Category |
|------|-------|----------|

### Sub-page fields

| Field | Required | Notes |
|-------|----------|-------|
| `Date` | Yes | Default to today |
| `Situation` | Yes | What happened, briefly |
| `What I learned` | Yes | The insight as a reusable principle |
| `What I'll do differently` | Yes | Concrete behavioral change, not aspiration |
| `Category` | Yes | `Technical`, `Communication`, `Process`, `People`, `Self-management` |

### Sub-page content format

```
**Date:** YYYY-MM-DD

**Situation:** ...

**What I learned:** ...

**What I'll do differently:** ...

**Category:** Technical
```

---

## Feedback

### Summary table columns

| Date | Title | Source | Type |
|------|-------|--------|------|

### Sub-page fields

| Field | Required | Notes |
|-------|----------|-------|
| `Date` | Yes | Default to today |
| `Source` | Yes | Role + relationship (e.g. "Manager", "Peer on backend team") |
| `Context` | Yes | What prompted it — 1:1, review, retro, offhand |
| `Feedback` | Yes | Verbatim quote where possible |
| `Type` | Yes | `Positive`, `Constructive`, `Mixed` |
| `My reaction` | Recommended | Initial gut response — separate from the feedback itself |
| `Action taken or planned` | Recommended | What the user is doing with it |

### Sub-page content format

```
**Date:** YYYY-MM-DD

**Source:** ...

**Context:** ...

**Feedback:** "..."

**Type:** Constructive

**My reaction:** ...

**Action taken or planned:** ...
```

---

## Discussion

### Summary table columns

| Date | Title | Who to discuss with | Status |
|------|-------|---------------------|--------|

### Sub-page fields

| Field | Required | Notes |
|-------|----------|-------|
| `Date opened` | Yes | Default to today |
| `Context` | Yes | Why it's on the user's mind |
| `My current thinking` | Recommended | Where the user is on this |
| `Who to discuss with` | Recommended | Manager, mentor, peer, etc. |
| `Status` | Yes | `Open`, `Discussed`, `Resolved` |
| `Outcome` | When resolved | Fill in when Status → Resolved |
| `Date closed` | When resolved | Fill in when Status → Resolved |

### Sub-page content format

```
**Date opened:** YYYY-MM-DD

**Context:** ...

**My current thinking:** ...

**Who to discuss with:** ...

**Status:** Open
```

When resolving:

```
**Status:** Resolved

**Outcome:** ...

**Date closed:** YYYY-MM-DD
```

---

## Summary table update procedure

When adding a new entry:
1. Fetch the section page to get the current table content (exact string needed for `old_str`).
2. Append a new row with `update_content`, using the sub-page URL as the title link.
3. The `old_str` must be the last row of the table (or the header if the table is empty).

Example append for Wins:
- `old_str`: the existing last row (or header line)
- `new_str`: existing last row + `\n| 2026-04-22 | [Title](url) | Impact summary | Complete |`
