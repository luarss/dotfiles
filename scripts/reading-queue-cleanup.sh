#!/bin/bash -eu
# reading-queue-cleanup.sh — launchd agent (weekday mornings) that sweeps checked-off
# ("- [x]") items out of the vault's reading-queue.md. The checkbox is the
# reject signal: checking an item marks it low-signal, this script removes it
# on the next run and decrements that batch's "(N kept)" header count. Fully
# emptied batches (every item in the section rejected) are dropped entirely.
#
# Deterministic, idempotent, offline: no model, no network, no MCP connectors
# (a scheduled reminder/cleanup routine must carry zero connectors). Removed
# items aren't discarded — they're appended to reading-queue-archive.md under
# a timestamped "## swept" section, so a bad click is still recoverable. It
# does NOT git commit/push — the vault-backup mechanism picks the change up,
# mirroring quarterly-landscape-reminder.sh.
#
# Env knobs (optional):
#   READING_QUEUE_NOTES_REPO   override notes repo (default: ~/work/notes)
#   READING_QUEUE_DRY_RUN=1    print what would change; write nothing

export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

NOTES_REPO="${READING_QUEUE_NOTES_REPO:-$HOME/work/notes}"
QUEUE="$NOTES_REPO/reading-queue.md"
ARCHIVE="$NOTES_REPO/reading-queue-archive.md"
DRY_RUN="${READING_QUEUE_DRY_RUN:-0}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

[ -f "$QUEUE" ] || { log "reading-queue.md not found at $QUEUE; nothing to do"; exit 0; }

# Cheap idempotency check: nothing checked, nothing to sweep.
if ! grep -qE '^- \[[xX]\]' "$QUEUE"; then
  log "no rejected items; no-op"
  exit 0
fi

[ -w "$QUEUE" ] || { log "reading-queue.md not writable; skipping"; exit 0; }

body_tmp="$(mktemp)"
archived_tmp="$(mktemp)"
trap 'rm -f "$body_tmp" "$archived_tmp"' EXIT

# Single pass: buffer each "## ... (N kept)" batch until the next header (or
# EOF), routing each 4-line item block (bullet/body/quote/[open] link) either
# into the batch buffer (kept) or the archive buffer (rejected). A batch is
# only emitted — header included — if at least one item survives.
awk -v arch="$archived_tmp" '
  function flush_batch(   i) {
    if (have_header) {
      if (batch_count > 0) {
        header = header_line
        sub(/\([0-9]+ kept\)/, "(" batch_count " kept)", header)
        print ""
        print header
        for (i = 1; i <= n_batch; i++) print batch_lines[i]
      }
    }
    have_header = 0
    n_batch = 0
    batch_count = 0
    delete batch_lines
  }
  function flush_item(   i) {
    if (checked) {
      for (i = 1; i <= n_item; i++) print item_lines[i] >> arch
      print "" >> arch
    } else {
      for (i = 1; i <= n_item; i++) batch_lines[++n_batch] = item_lines[i]
      batch_count++
    }
    in_item = 0
    n_item = 0
    delete item_lines
  }
  {
    if (in_item) {
      item_lines[++n_item] = $0
      if ($0 ~ /^  \[open\]\(/) flush_item()
      next
    }
    if ($0 ~ /^## /) {
      flush_batch()
      header_line = $0
      have_header = 1
      next
    }
    if ($0 ~ /^- \[/) {
      in_item = 1
      n_item = 1
      item_lines[1] = $0
      checked = ($0 ~ /^- \[[xX]\]/) ? 1 : 0
      next
    }
    if (have_header) {
      batch_lines[++n_batch] = $0
    } else {
      print
    }
  }
  END {
    if (in_item) flush_item()   # unterminated block: keep it rather than lose it
    flush_batch()
  }
' "$QUEUE" | cat -s > "$body_tmp"

old_items=$(grep -c '^- \[' "$QUEUE")
new_items=$(grep -c '^- \[' "$body_tmp")
removed=$(( old_items - new_items ))
old_headers=$(grep -c '^## ' "$QUEUE")
new_headers=$(grep -c '^## ' "$body_tmp")
dropped_batches=$(( old_headers - new_headers ))

# Sanity: the archive should hold exactly the items that vanished from the body.
archived=$(grep -c '^- \[' "$archived_tmp" || true)
if [ "$archived" -ne "$removed" ]; then
  log "ERROR: archived item count ($archived) != removed count ($removed); aborting"
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN — would remove $removed item(s), drop $dropped_batches emptied batch(es)"
  exit 0
fi

mv "$body_tmp" "$QUEUE"

# Resolve before the append redirection below opens/creates the file — an
# open-for-append on a nonexistent path creates it (empty) as setup, so an
# existence check inside the redirected group would always see it present.
archive_is_new=1
[ -f "$ARCHIVE" ] && archive_is_new=0

{
  [ "$archive_is_new" = 1 ] && printf '# Reading Queue Archive\n\n_Items rejected from reading-queue.md, newest sweep on top._\n'
  printf '\n## swept %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  cat "$archived_tmp"
} >> "$ARCHIVE"

log "removed $removed item(s), dropped $dropped_batches emptied batch(es); archived to $ARCHIVE"
