# Example entries

Worked examples showing the level of detail, phrasing, and structure that makes entries useful later. Consult when the user's input is sparse and you need a model to guide your follow-up questions, or when helping them phrase a field.

The examples here are intentionally a bit dry — they prioritize clarity and future-usefulness over flourish. Don't add adjectives or hype when logging the user's actual entries.

---

## Wins

### Good example: specific, quantified, with evidence

- **Title**: Cut CI pipeline time from 22min to 6min
- **Date**: 2026-03-14
- **What I did**: Identified that the test suite was re-installing dependencies on every run. Switched to a cached base image and parallelized the integration tests across 4 workers.
- **Impact**: Saved ~16min per PR × ~40 PRs/week across the team = ~10 engineer-hours/week. Eliminated a major source of context-switch frustration raised in two retros.
- **Skills demonstrated**: Technical depth, Execution
- **Evidence**: https://github.com/org/repo/pull/2847, retro doc link
- **Status**: Complete

### Good example: impact still unknown

- **Title**: Led migration planning for auth service rewrite
- **Date**: 2026-04-01
- **What I did**: Ran 3 scoping sessions with backend and security teams, drafted migration RFC covering 4 service dependencies.
- **Impact**: TBD — will measure post-migration in Q3. Intermediate: RFC approved by security lead and staff eng on first review.
- **Skills demonstrated**: Cross-functional, Strategy
- **Evidence**: RFC doc link
- **Status**: Needs-followup

### What to push back on

If the user says "shipped the dashboard feature" and nothing else — that's a task, not a win. Ask: what made this notable? Did it unblock someone, hit a deadline, solve something tricky, get positive feedback? If they can't name anything, it might not belong in Wins — could be a regular work log instead.

---

## Learnings

### Good example

- **Title**: Share rough work earlier, not polished work later
- **Date**: 2026-02-20
- **Situation**: Spent two weeks building a detailed proposal for the payments redesign. When I presented it, the director immediately surfaced a constraint I hadn't known about that invalidated half the approach.
- **What I learned**: When working on anything cross-functional, a rough sketch shared at day 2 gets me the constraints I need far cheaper than a polished deck shared at day 10. Polish is only valuable once the direction is locked.
- **What I'll do differently**: For the next cross-functional project, share a one-page outline with the director within the first 3 days before doing any detailed work. Set a calendar reminder at project kickoff.
- **Category**: Communication

### Good example

- **Title**: Estimate ranges, not points
- **Date**: 2026-03-02
- **Situation**: Committed to shipping the search refactor in 3 weeks. Hit 5 weeks. Manager didn't mind the slip but my own planning downstream broke.
- **What I learned**: Single-point estimates hide my uncertainty from myself as much as from others. A range ("3-6 weeks, most likely 4") would have let me plan the downstream work honestly.
- **What I'll do differently**: Always give ranges on estimates longer than one week. Write the P50 and P90 separately in the planning doc.
- **Category**: Self-management

### What to push back on

"I need to communicate better" — too vague. Ask what specifically, in what situation, and what's the concrete next-time behavior. Good learnings have a story behind them (the Situation field) and a testable behavior change.

---

## Feedback

### Good example: constructive, with user reaction separated

- **Title**: Slow to escalate blockers — manager 1:1
- **Date**: 2026-01-19
- **Source**: Manager
- **Context**: Weekly 1:1, came up after I mentioned the API latency issue had been blocking me for 4 days.
- **Feedback**: "I'd rather hear about a blocker at day one than find out at day four. When you wait, I can't help, and the team can't reprioritize. If you're unsure whether something counts as a blocker, err on the side of raising it."
- **Type**: Constructive
- **My reaction**: Defensive at first — felt like I was being told I couldn't problem-solve on my own. Thinking about it later, the point wasn't about capability, it was about information flow.
- **Action taken or planned**: Adding a "blockers" line to my weekly status update, even if empty. Raising anything that's cost me >half a day in our Slack DM same-day.

### Good example: positive

- **Title**: Strong RFC writing — from staff eng
- **Date**: 2026-02-08
- **Source**: Staff engineer (skip-level peer)
- **Context**: After design review for the caching RFC.
- **Feedback**: "This is one of the clearest RFCs I've read here. The 'alternatives considered' section especially — most people skip that or make it a formality, but yours shows real analysis."
- **Type**: Positive
- **My reaction**: Validating — I'd specifically put effort into the alternatives section because I used to skip it myself.
- **Action taken or planned**: Offered to share template/approach in the next eng guild meeting.

### What to push back on

If the user summarizes feedback in their own words ("basically my manager said I should communicate more") — push for the actual quote. Paraphrasing loses specificity and often softens criticism. "Try to remember what they actually said — even fragments help."

---

## Discussion

### Good example

- **Title**: Should I push for promotion this cycle or next?
- **Date opened**: 2026-04-10
- **Context**: Performance conversations start in 6 weeks. I've hit most of the senior criteria but the "influence beyond team" bar is ambiguous for my role.
- **My current thinking**: Leaning toward pushing this cycle. Worst case it's a no and I get explicit criteria for next time. Risk is if it's seen as premature, it could affect next cycle's framing.
- **Who to discuss with**: Manager (directly), mentor in other org (for outside perspective)
- **Status**: Open

### Good example (after resolution)

- **Title**: Should I push for promotion this cycle or next?
- **Status**: Resolved
- **Outcome**: Discussed with manager April 22. She said push this cycle — she'd been planning to suggest it. Also got concrete criteria for the "influence" dimension: 2 cross-team initiatives where I drove outcomes, which the auth migration and RFC template work both count for.
- **Date closed**: 2026-04-22

### What to push back on

If the user opens a Discussion with only a topic and no context ("Discussion: career path"), that's not useful future-you. Ask what specifically is on their mind right now — the Context field is what makes the entry retrievable and actionable later.

---

## Cross-entry notes

**When an entry spans categories.** A single event can generate a win, a learning, and feedback received — that's fine, log them separately, one in each database. Don't try to cram it all into one entry. Cross-reference by mentioning the other entry's title in a rich-text field if useful.

**When the user is venting.** Sometimes what starts as "log this feedback" is actually processing. Log the feedback accurately, but don't rush them through the questions. Their reaction field can capture some of the emotional content.

**When in doubt about which database.** If the user says "I want to log X" without specifying: Wins is for things they did that mattered. Learnings is for insights from experience. Feedback is for input from others. Discussion is for open questions. Ask if unclear.
