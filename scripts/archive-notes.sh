#!/bin/bash -eu

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SOURCE_DIR="${NOTES_ARCHIVE_SOURCE_DIR:-$HOME/work/notes}"
ARCHIVE_DIR="${NOTES_ARCHIVE_DIR:-$HOME/work/archives/notes}"
DRY_RUN="${NOTES_ARCHIVE_DRY_RUN:-0}"
LOCKDIR="$HOME/.claude/.archive-notes.lock"
TODAY="$(date +%Y-%m-%d)"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

[ -d "$ARCHIVE_DIR" ] || { log "archive dir absent ($ARCHIVE_DIR); nothing to do"; exit 0; }
[ -d "$SOURCE_DIR" ] || { log "source dir absent ($SOURCE_DIR); nothing to do"; exit 0; }
command -v rsync >/dev/null 2>&1 || die "rsync not found on PATH"

mkdir -p "$(dirname "$LOCKDIR")"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  log "another run holds the lock ($LOCKDIR); exiting"
  exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

CURRENT_DIR="$ARCHIVE_DIR/current"
VERSIONS_DIR="$ARCHIVE_DIR/versions/$TODAY"
mkdir -p "$CURRENT_DIR"

RSYNC_ARGS=(
  -a --delete --itemize-changes
  --backup --backup-dir="$VERSIONS_DIR"
  --exclude=/.git/
  --exclude=/.claude
  --exclude=/.venv-pptx/
  --exclude=/.scratch/
  --exclude=.trash/
  --exclude=__pycache__/
  --exclude=.pytest_cache/
  --exclude=.DS_Store
  --exclude='.obsidian/workspace*'
  --exclude='*.swp'
)
[ "$DRY_RUN" = "1" ] && RSYNC_ARGS+=(--dry-run)

changes="$(rsync "${RSYNC_ARGS[@]}" "$SOURCE_DIR/" "$CURRENT_DIR/" | grep -c '^[<>c*]' || true)"

if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN — $changes change(s) would be mirrored to $CURRENT_DIR"
  exit 0
fi

log "done: $changes change(s) mirrored to $CURRENT_DIR (replaced/deleted files kept in $VERSIONS_DIR)"
