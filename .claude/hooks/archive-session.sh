#!/usr/bin/env bash
# SessionEnd hook — real-time archival of the just-finished Claude Code session.
#
# Copies the session's transcript (.jsonl) into a Google-Drive-mirrored folder
# the moment the session ends, so a transcript is preserved even if Claude Code
# later prunes it locally (time-based `cleanupPeriodDays` OR aggressive
# disk-pressure cleanup). This is the capture-at-creation layer; the weekday
# `scripts/archive-session-logs.sh` sweep is the batch reconciliation layer.
#
# Wired in settings.base.json (all profiles) so EVERY session — default and
# third-party providers — is captured. It self-gates on the archive dir
# existing, so machines without the Drive mirror set up (personal laptops,
# Linux) simply no-op.
#
# The archive dir is a REAL directory registered as a Google Drive "mirror"
# folder (Drive for Desktop does not sync symlinks), so writing a real file
# here syncs it to Drive with no Full Disk Access needed.
#
# Never blocks: always exits 0 so a copy failure can't disrupt session end.
set -u

# Work laptop only — same switch skill-scan-guard.sh and the sonnet switch use.
WORK_HOSTNAME="${DOTFILES_WORK_HOSTNAME:-Shuis-MacBook-Air}"
[ "$(hostname -s 2>/dev/null)" = "$WORK_HOSTNAME" ] || exit 0

# Destination root — a real dir mirrored to Google Drive. Override for tests.
ARCHIVE_DIR="${CLAUDE_ARCHIVE_DIR:-$HOME/work/archives/claude-sessions}"

# No mirror set up here (personal machine / Linux) → nothing to do.
[ -d "$ARCHIVE_DIR" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

PAYLOAD=$(cat)
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$PAYLOAD" 2>/dev/null)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Preserve the encoded project dir as a subfolder so sessions from different
# projects never collide (session ids are unique, but this keeps the mirror
# browsable and matches the on-disk layout).
PROJECT=$(basename "$(dirname "$TRANSCRIPT")")
DEST_DIR="$ARCHIVE_DIR/live/$PROJECT"
DEST="$DEST_DIR/$(basename "$TRANSCRIPT")"

mkdir -p "$DEST_DIR" || exit 0

# Atomic copy: write to a temp file in the same dir, then rename over the
# destination so Drive never syncs a half-written transcript.
TMP="$DEST.tmp.$$"
if cp "$TRANSCRIPT" "$TMP" 2>/dev/null; then
  mv -f "$TMP" "$DEST" 2>/dev/null || rm -f "$TMP"
fi
exit 0
