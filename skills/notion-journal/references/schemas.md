# Database schemas

Exact property definitions for each of the four databases. Use these property names and types verbatim when calling the Notion MCP — case and spacing matter.

When verifying an existing database, check that each property listed here exists with the specified type. If not, tell the user before proceeding.

---

## Wins

| Property | Type | Notes |
|---|---|---|
| `Title` | Title | One-line summary (e.g. "Cut deploy time from 20min to 4min") |
| `Date` | Date | Default to today |
| `What I did` | Rich text | 2–3 sentences, concrete actions |
| `Impact` | Rich text | Quantified if possible. Never leave blank; use "TBD" + Status tag if unknown |
| `Skills demonstrated` | Multi-select | Options: `Leadership`, `Technical depth`, `Cross-functional`, `Communication`, `Mentorship`, `Strategy`, `Execution`, `Product sense`, `Design` |
| `Evidence` | URL or Rich text | Links to PR, doc, Slack thread, dashboard |
| `Quarter` | Formula | Auto-derived from Date (e.g. "2026-Q2") |
| `Status` | Select | Options: `Complete`, `Needs-followup` |

---

## Learnings

| Property | Type | Notes |
|---|---|---|
| `Title` | Title | Short phrase capturing the insight (e.g. "Share rough work earlier") |
| `Date` | Date | Default to today |
| `Situation` | Rich text | What happened, briefly |
| `What I learned` | Rich text | The insight as a reusable principle |
| `What I'll do differently` | Rich text | Concrete behavioral change, not aspiration |
| `Category` | Select | Options: `Technical`, `Communication`, `Process`, `People`, `Self-management` |
| `Quarter` | Formula | Auto-derived from Date |

---

## Feedback

| Property | Type | Notes |
|---|---|---|
| `Title` | Title | Short summary (e.g. "Slow to escalate blockers — from manager 1:1") |
| `Date` | Date | Default to today |
| `Source` | Rich text | Who gave it (role + relationship, e.g. "Manager", "Peer on backend team", "Skip-level") |
| `Context` | Rich text | What prompted it — 1:1, review, project retro, offhand |
| `Feedback` | Rich text | Verbatim quote where possible |
| `Type` | Select | Options: `Positive`, `Constructive`, `Mixed` |
| `My reaction` | Rich text | Initial gut response — keep separate from Feedback |
| `Action taken or planned` | Rich text | What the user is doing with it |
| `Quarter` | Formula | Auto-derived from Date |

---

## Discussion

| Property | Type | Notes |
|---|---|---|
| `Title` | Title | The topic or question |
| `Date opened` | Date | Default to today |
| `Context` | Rich text | Why it's on the user's mind |
| `My current thinking` | Rich text | Where the user is on this |
| `Who to discuss with` | Rich text | Manager, mentor, peer, etc. |
| `Status` | Select | Options: `Open`, `Discussed`, `Resolved` |
| `Outcome` | Rich text | Filled in when status changes to Resolved |
| `Date closed` | Date | Filled in when status changes to Resolved |

---

## Quarter formula

For databases with a `Quarter` formula property, use this Notion formula:

```
formatDate(prop("Date"), "YYYY") + "-Q" + toString(ceil(month(prop("Date")) / 3))
```

For the Discussion database, replace `prop("Date")` with `prop("Date opened")`.

## Property creation via Notion MCP

When creating or updating entries, the Notion MCP expects properties shaped like:

- **Title**: `{ "title": [{ "text": { "content": "..." } }] }`
- **Rich text**: `{ "rich_text": [{ "text": { "content": "..." } }] }`
- **Date**: `{ "date": { "start": "YYYY-MM-DD" } }`
- **Select**: `{ "select": { "name": "OptionName" } }`
- **Multi-select**: `{ "multi_select": [{ "name": "Opt1" }, { "name": "Opt2" }] }`
- **URL**: `{ "url": "https://..." }`

Exact payload shapes may vary by MCP implementation — if a call fails, inspect the error and adjust, but start from this format.
