#!/bin/bash -eu
# archive-session-logs.sh — weekday-morning reconciliation sweep that bundles
# Claude Code session transcripts into a dated tarball inside a Google-Drive-
# mirrored folder.
#
# This is the batch catch-all layer. The real-time layer is the SessionEnd hook
# (.claude/hooks/archive-session.sh), which copies each transcript the moment a
# session ends. This sweep exists to catch anything the hook missed — crashes
# before SessionEnd fired, sessions from other machines, backfill — and to
# produce point-in-time tar snapshots.
#
# Robustness (so the sweep itself can never permanently drop a session):
#   - Append-only: every run writes a NEW dated tarball; nothing is ever deleted
#     from the archive, so a locally-pruned session's last snapshot persists.
#   - Lookback overlap: each run re-scans at least the last LOOKBACK_DAYS (not a
#     strict since-watermark window), so a corrupted watermark or a skipped run
#     never leaves a permanent gap. After a long outage the (older) watermark
#     drives a full catch-up instead.
#
# The archive dir is a REAL directory registered as a Google Drive "mirror"
# folder — Drive for Desktop does not sync symlinks, and mirror mode keeps files
# in a normal local path, so no Full Disk Access is needed.
#
# Env knobs (all optional):
#   CLAUDE_ARCHIVE_DIR            mirror root (default ~/work/archives/claude-sessions)
#   CLAUDE_ARCHIVE_PROJECTS_DIR   source transcripts (default ~/.claude/projects)
#   CLAUDE_ARCHIVE_LOOKBACK_DAYS  minimum re-scan window in days (default 7)
#   CLAUDE_ARCHIVE_DRY_RUN=1      list what would be archived; write no tarball

export PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

ARCHIVE_DIR="${CLAUDE_ARCHIVE_DIR:-$HOME/work/archives/claude-sessions}"
PROJECTS_DIR="${CLAUDE_ARCHIVE_PROJECTS_DIR:-$HOME/.claude/projects}"
LOOKBACK_DAYS="${CLAUDE_ARCHIVE_LOOKBACK_DAYS:-7}"
DRY_RUN="${CLAUDE_ARCHIVE_DRY_RUN:-0}"
WATERMARK="$HOME/.claude/.archive-session-logs.watermark"
LOCKDIR="$HOME/.claude/.archive-session-logs.lock"
TODAY="$(date +%Y-%m-%d)"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }
# epoch (seconds) -> `touch -t` stamp, portable across BSD (macOS) and GNU date.
epoch_stamp() { date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S; }
# N-days-ago epoch, portable (BSD `-v`, else GNU `-d`).
epoch_days_ago() { date -v-"$1"d +%s 2>/dev/null || date -d "$1 days ago" +%s; }

# --- preconditions -----------------------------------------------------------
# No mirror set up here (personal machine / no Drive mirror) → nothing to do.
[ -d "$ARCHIVE_DIR" ] || { log "archive dir absent ($ARCHIVE_DIR); nothing to do"; exit 0; }
[ -d "$PROJECTS_DIR" ] || { log "no projects dir; nothing to do"; exit 0; }
command -v tar >/dev/null 2>&1 || die "tar not found on PATH"

# Single-instance guard (mkdir is atomic). Ensure the parent exists first so a
# missing ~/.claude isn't misread as a held lock.
mkdir -p "$(dirname "$LOCKDIR")"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "another run holds the lock ($LOCKDIR); exiting"
  exit 0
fi
SCRATCH="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH"; rmdir "$LOCKDIR" 2>/dev/null || true; }
trap cleanup EXIT

# Marker whose mtime is this run's start instant; persisted as the watermark on
# success (touch -r) at full filesystem precision.
RUN_MARKER="$SCRATCH/run-start.marker"
touch "$RUN_MARKER"

# --- choose the scan reference (older of watermark and the lookback floor) ----
# The lookback floor guarantees at least LOOKBACK_DAYS of overlap every run; the
# watermark extends the window further back after a missed/failed run.
LOOKBACK_REF="$SCRATCH/lookback.ref"
touch -t "$(epoch_stamp "$(epoch_days_ago "$LOOKBACK_DAYS")")" "$LOOKBACK_REF"
if [ -f "$WATERMARK" ] && [ "$WATERMARK" -ot "$LOOKBACK_REF" ]; then
  REF="$WATERMARK"
  log "scanning since watermark (older than ${LOOKBACK_DAYS}d floor)"
else
  REF="$LOOKBACK_REF"
  log "scanning last ${LOOKBACK_DAYS}d (lookback floor)"
fi

# --- collect transcripts modified since REF (all projects) -------------------
# Relative paths (from PROJECTS_DIR) so the tarball preserves the project layout
# without leading-slash rewriting.
LIST="$SCRATCH/list"
( cd "$PROJECTS_DIR" && find . -name '*.jsonl' -newer "$REF" 2>/dev/null | sort ) > "$LIST"
count="$(wc -l < "$LIST" | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  log "no transcripts modified since reference; updating watermark and exiting"
  touch -r "$RUN_MARKER" "$WATERMARK"
  exit 0
fi
log "found $count transcript(s) to archive"

# --- write the dated tarball into the mirror (append-only) --------------------
SWEEP_DIR="$ARCHIVE_DIR/sweeps"
OUT="$SWEEP_DIR/$TODAY.tar.gz"
if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN — would write $count transcript(s) to $OUT:"
  cat "$LIST"
  touch -r "$RUN_MARKER" "$WATERMARK"
  exit 0
fi

mkdir -p "$SWEEP_DIR"
# Write to a temp file first, then rename over the destination so Drive never
# syncs a half-written tarball. A same-day rerun overwrites the day's snapshot
# (idempotent) with the latest, wider capture.
TMP="$SCRATCH/sweep.tar.gz"
( cd "$PROJECTS_DIR" && tar -czf "$TMP" -T "$LIST" )
mv -f "$TMP" "$OUT"

touch -r "$RUN_MARKER" "$WATERMARK"
log "done: archived $count transcript(s) to $OUT"
