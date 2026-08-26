---
name: done
description: Record what was accomplished in the current chat session into the latest weekly note under ~/work/notes/NUS-Enterprise/Weekly/. Use for /done or any ask to log/save/record this session's work into the weekly notes.
argument-hint: "(optional) short label for this session's work"
disable-model-invocation: true
---

# /done — Log this session into the weekly note

Summarize what was accomplished in the **current chat session** and append it to the **latest weekly note** in `~/work/notes/NUS-Enterprise/Weekly/`. Keep it lightweight — this should take seconds, not a back-and-forth.

## Steps

1. **Resolve the target file.** Pick the latest ISO-week note in `~/work/notes/NUS-Enterprise/Weekly/`:

   ```bash
   ls ~/work/notes/NUS-Enterprise/Weekly/[0-9]*-W[0-9]*.md \
     | sed -E 's|.*/([0-9]{4}-W[0-9]{2}).*|\1|' | sort -u | tail -1
   ```

   Use the base note for that week — `<WEEK>.md` (e.g. `2026-W31.md`), not a numbered variant like `<WEEK>-2.md`. If that base file is missing but numbered variants exist, target the base name and create it. If the whole `Weekly/` directory is empty or missing, tell the user and stop.

2. **Build the summary from this session.** Review the conversation and write terse, concrete bullets of what was actually done — files changed, decisions made, problems solved, commands run that mattered. Skip filler. Reference artifacts by path rather than restating them. If the user passed an argument, use it as the entry heading/label.

3. **Compose the entry** to append at the end of the target file:

   ```markdown
   ## Session log — <YYYY-MM-DD> <label or short title>

   - <what was done>
   - <what was done>
   ...
   ```

   Date is today (`date +%Y-%m-%d`).

4. **Show the entry as a preview** and ask "Append to `Weekly/<WEEK>.md`?" Wait for confirmation.

5. **On confirm**, append the entry to the end of the file (read the last line, Edit with it as `old_str` + the entry appended, or Write the concatenated content).

6. Reply with one line: confirmation + the relative path from `~/work/notes/` + bullet count.

## Principles

- **Lightweight.** One preview, one confirmation, done. Don't interrogate the user.
- **Concrete over complete.** Log what changed and why it mattered, not a transcript.
- **Don't editorialize or inflate.** Plain record of the work.
- **Redact secrets.** No tokens, keys, or credentials in the note.
