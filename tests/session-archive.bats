#!/usr/bin/env bats
# Tests for the session-transcript archive:
#   - .claude/hooks/archive-session.sh   (SessionEnd real-time copy)
#   - scripts/archive-session-logs.sh    (weekday reconciliation sweep)
#
# Fully offline. HOME is redirected to a temp dir so the watermark/lock live
# there; the archive dir and projects dir are pointed at fixtures via the
# scripts' CLAUDE_ARCHIVE_* env knobs.

setup_file() {
  export DOTFILES_WORK_HOSTNAME="$(hostname -s)"

  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOOK="$base/.claude/hooks/archive-session.sh"
  export SWEEP="$base/scripts/archive-session-logs.sh"
  export TODAY; TODAY="$(date +%Y-%m-%d)"
  export TOUCH_30D; TOUCH_30D="$(date -v-30d +%Y%m%d%H%M.%S 2>/dev/null || date -d '30 days ago' +%Y%m%d%H%M.%S)"
  export TOUCH_2D; TOUCH_2D="$(date -v-2d +%Y%m%d%H%M.%S 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M.%S)"
  export YDAY; YDAY="$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d)"
}

setup() {
  ROOT="$(mktemp -d)"
  export HOME="$ROOT/home"
  export CLAUDE_ARCHIVE_DIR="$ROOT/archive"
  export CLAUDE_ARCHIVE_PROJECTS_DIR="$ROOT/projects"
  PROJ="$CLAUDE_ARCHIVE_PROJECTS_DIR/-Users-tester-work-demo"
  mkdir -p "$HOME/.claude" "$CLAUDE_ARCHIVE_DIR" "$PROJ"
  SESSION="$PROJ/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' > "$SESSION"
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

@test "hook: removes the .tmp partial when cancelled mid-copy" {
  local stub="$ROOT/stub-bin"
  mkdir -p "$stub"
  local copying="$ROOT/copying"
  # Copy the file to create the .tmp partial, publish our PID so the test can
  # interrupt us immediately after signalling the hook, and block in sleep.
  printf '#!/bin/sh\n/bin/cp "$@"\necho "$$" > "%s"\nexec sleep 10\n' "$copying" > "$stub/cp"
  chmod +x "$stub/cp"

  PATH="$stub:$PATH" bash "$HOOK" <<<"{\"transcript_path\":\"$SESSION\"}" &
  local hook_pid=$!
  local attempts=0
  until [ -s "$copying" ] || [ "$attempts" -ge 200 ]; do
    sleep 0.02
    attempts=$((attempts + 1))
  done
  [ -s "$copying" ]
  local cp_pid; cp_pid="$(cat "$copying")"
  kill -TERM "$hook_pid"
  kill -TERM "$cp_pid" 2>/dev/null || true
  wait "$hook_pid" || true

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
  touch -t "$TOUCH_30D" "$SESSION"
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
  touch -t "$TOUCH_2D" "$recent"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run tar tzf "$CLAUDE_ARCHIVE_DIR/sweeps/$TODAY.tar.gz"
  [[ "$output" == *"bbbbbbbb-2222.jsonl"* ]]
}

@test "sweep: append-only — a prior day's tarball is never removed" {
  # Simulate yesterday's sweep output.
  mkdir -p "$CLAUDE_ARCHIVE_DIR/sweeps"
  echo old > "$CLAUDE_ARCHIVE_DIR/sweeps/$YDAY.tar.gz"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_ARCHIVE_DIR/sweeps/$YDAY.tar.gz" ]      # untouched
  [ -f "$CLAUDE_ARCHIVE_DIR/sweeps/$TODAY.tar.gz" ]     # today's added
}
