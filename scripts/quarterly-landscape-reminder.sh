#!/bin/bash -eu
# quarterly-landscape-reminder.sh — launchd agent (1st of Jan/Apr/Jul/Oct) that
# resurfaces the "refresh the AI landscape diagram" action in the vault TODO
# backlog, so NUS-Enterprise/etp-vendor-architecture-2026.html gets reviewed once
# a quarter. Deterministic, idempotent, offline: no model, no network, no MCP
# connectors (a scheduled reminder routine must carry zero connectors).
#
# It appends ONE TODO card under the "## 📥 Inbox" section of
# NUS-Enterprise/TODO.md, guarded by an HTML-comment marker unique to the quarter,
# so reruns within the same quarter are no-ops. It does NOT git commit/push — the
# vault-backup mechanism picks the change up, mirroring tools/new-week.sh.
#
# Env knobs (optional):
#   LANDSCAPE_NOTES_REPO   override notes repo (default: ~/work/notes)
#   LANDSCAPE_DRY_RUN=1    print the card that would be inserted; write nothing

export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

NOTES_REPO="${LANDSCAPE_NOTES_REPO:-$HOME/work/notes}"
TODO="$NOTES_REPO/NUS-Enterprise/TODO.md"
DRY_RUN="${LANDSCAPE_DRY_RUN:-0}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

[ -f "$TODO" ] || { log "TODO.md not found at $TODO; nothing to do"; exit 0; }

# Quarter identity: Q1=Jan-Mar, Q2=Apr-Jun, Q3=Jul-Sep, Q4=Oct-Dec.
year="$(date +%Y)"
month="$(date +%-m)"
today="$(date +%F)"
quarter=$(( (month - 1) / 3 + 1 ))
marker="quarterly-landscape ${year}-Q${quarter}"

# Idempotent: bail if this quarter's card is already present.
if grep -qF "$marker" "$TODO"; then
  log "card for ${year}-Q${quarter} already present; no-op"
  exit 0
fi

# The card. Body stays within the 2-line rule; the marker rides in an invisible
# HTML comment on the next: line.
card="- [ ] **Refresh the AI landscape diagram** \`id:refresh-ai-landscape\` \`todo\`
      fields: review:${today} · project:[[etp-vendor-architecture-2026.html]]
      next: quarterly refresh — re-run the \`architecture-diagram\` skill over every live project; reconcile against \`projects/\` + TODO.md. <!-- ${marker} -->"

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN — would insert under '## 📥 Inbox':"
  printf '%s\n' "$card"
  exit 0
fi

[ -w "$TODO" ] || { log "TODO.md not writable; skipping"; exit 0; }

tmp="$(mktemp)"
CARD="$card" TODAY="$today" awk '
  BEGIN { fm = 0; bumped = 0; inserted = 0 }
  # Bump the first frontmatter `updated:` line (inside the leading --- block only).
  /^---[[:space:]]*$/ { fm++ }
  fm == 1 && !bumped && /^updated:/ {
    print "updated: " ENVIRON["TODAY"]; bumped = 1; next
  }
  { print }
  # Splice the card in right after the Inbox header.
  !inserted && /^## 📥 Inbox[[:space:]]*$/ {
    print ""; print ENVIRON["CARD"]; inserted = 1
  }
  END {
    # No Inbox section? Fall back to appending one at EOF.
    if (!inserted) {
      print ""; print "## 📥 Inbox"; print ""; print ENVIRON["CARD"]
    }
  }
' "$TODO" > "$tmp"

# Sanity: never shrink the file (guards against a botched awk pass).
if [ "$(wc -c < "$tmp")" -lt "$(wc -c < "$TODO")" ]; then
  log "ERROR: rewritten TODO.md is smaller than original; aborting"
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$TODO"
log "inserted ${year}-Q${quarter} landscape-refresh card into $TODO"
