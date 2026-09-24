#!/usr/bin/env bats
# Tests for the session-transcript archive:
#   - .claude/hooks/archive-session.sh   (SessionEnd real-time copy)
#   - scripts/archive-session-logs.sh    (weekday reconciliation sweep)
#
# Fully offline. HOME is redirected to a temp dir so the watermark/lock live
# there; the archive dir and projects dir are pointed at fixtures via the
# scripts' CLAUDE_ARCHIVE_* env knobs.

setup() {
  export DOTFILES_WORK_HOSTNAME="$(hostname -s)"

  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$base/.claude/hooks/archive-session.sh"
  SWEEP="$base/scripts/archive-session-logs.sh"

  ROOT="$(mktemp -d)"
  export HOME="$ROOT/home"
  mkdir -p "$HOME/.claude"

  export CLAUDE_ARCHIVE_DIR="$ROOT/archive"
  export CLAUDE_ARCHIVE_PROJECTS_DIR="$ROOT/projects"
  mkdir -p "$CLAUDE_ARCHIVE_DIR"

  PROJ="$CLAUDE_ARCHIVE_PROJECTS_DIR/-Users-tester-work-demo"
  mkdir -p "$PROJ"
  SESSION="$PROJ/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' > "$SESSION"

  export TODAY; TODAY="$(date +%Y-%m-%d)"
}

teardown() { rm -rf "$ROOT"; }

# --- SessionEnd hook ---------------------------------------------------------

@test "hook: copies the transcript into <archive>/live/<project>/" {
  run bash "$HOOK" <<<"{\"transcript_path\":\"$SESSION\"}"
  [ "$status" -eq 0 ]
  local dest="$CLAUDE_ARCHIVE_DIR/live/-Users-tester-work-demo/$(basename "$SESSION")"
  [ -f "$dest" ]
  diff "$SESSION" "$dest"
}

@test "hook: no-op (exit 0, no dir) when the archive dir is absent" {
  export CLAUDE_ARCHIVE_DIR="$ROOT/missing"
  run bash "$HOOK" <<<"{\"transcript_path\":\"$SESSION\"}"
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/missing" ]
}

@test "hook: no-op when payload lacks a transcript_path" {
  run bash "$HOOK" <<<"{}"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_ARCHIVE_DIR/live" ]
}

@test "hook: no-op when the transcript file does not exist" {
  run bash "$HOOK" <<<"{\"transcript_path\":\"$ROOT/nope.jsonl\"}"
  [ "$status" -eq 0 ]
  [ ! -e "$CLAUDE_ARCHIVE_DIR/live" ]
}

@test "hook: leaves no .tmp partial behind after a successful copy" {
  run bash "$HOOK" <<<"{\"transcript_path\":\"$SESSION\"}"
  [ "$status" -eq 0 ]
  run find "$CLAUDE_ARCHIVE_DIR" -name "*.tmp.*"
  [ -z "$output" ]
}

# --- weekday sweep -----------------------------------------------------------

@test "sweep: writes a dated tarball containing the transcript" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  local out="$CLAUDE_ARCHIVE_DIR/sweeps/$TODAY.tar.gz"
  [ -f "$out" ]
  run tar tzf "$out"
  [[ "$output" == *"aaaaaaaa-1111-2222-3333-444444444444.jsonl"* ]]
}

@test "sweep: dry run writes no tarball" {
  run env CLAUDE_ARCHIVE_DRY_RUN=1 bash "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [ ! -e "$CLAUDE_ARCHIVE_DIR/sweeps" ]
}

@test "sweep: no-op when the archive dir is absent" {
  export CLAUDE_ARCHIVE_DIR="$ROOT/missing"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "sweep: watermark advances so a second run finds nothing new" {
  run bash "$SWEEP"; [ "$status" -eq 0 ]
  # Age the sole session well past the lookback floor so only the watermark
  # (which the first run advanced to 'now') governs selection.
  touch -t "$(date -v-30d +%Y%m%d%H%M.%S 2>/dev/null || date -d '30 days ago' +%Y%m%d%H%M.%S)" "$SESSION"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no transcripts modified since reference"* ]]
}

@test "sweep: lookback floor re-captures a file older than the watermark" {
  # First run advances the watermark to now.
  run bash "$SWEEP"; [ "$status" -eq 0 ]
  # A file modified 2 days ago is older than the watermark but within the
  # default 7-day lookback floor, so the next run must still capture it.
  local recent="$PROJ/bbbbbbbb-2222.jsonl"
  printf '{"type":"user"}\n' > "$recent"
  touch -t "$(date -v-2d +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M.%S)" "$recent"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run tar tzf "$CLAUDE_ARCHIVE_DIR/sweeps/$TODAY.tar.gz"
  [[ "$output" == *"bbbbbbbb-2222.jsonl"* ]]
}

@test "sweep: append-only — a prior day's tarball is never removed" {
  # Simulate yesterday's sweep output.
  mkdir -p "$CLAUDE_ARCHIVE_DIR/sweeps"
  local yday; yday="$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d)"
  echo old > "$CLAUDE_ARCHIVE_DIR/sweeps/$yday.tar.gz"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_ARCHIVE_DIR/sweeps/$yday.tar.gz" ]      # untouched
  [ -f "$CLAUDE_ARCHIVE_DIR/sweeps/$TODAY.tar.gz" ]     # today's added
}
