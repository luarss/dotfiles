#!/usr/bin/env bats
# Tests for scripts/daily-session-log.sh
#
# All external services are stubbed so these run offline:
#   - curl  -> a stub that emits a canned Gemini generateContent response
#              (bullets from $STUB_BULLETS, default one concrete bullet).
#   - gh    -> a stub that records `pr create`/`pr view` calls to a file.
#   - git   -> real; pushes go to a local bare "origin", so the full
#              worktree/commit/push path exercises without network.
#
# HOME is redirected to a temp dir so the watermark/lock/projects live there.
# The script's env knobs (SESSION_LOG_*) point discovery + notes repo at
# fixtures we build in setup.

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/daily-session-log.sh"
  ROOT="$(mktemp -d)"
  export HOME="$ROOT/home"
  mkdir -p "$HOME/.claude/projects"

  # Stub bin dir, put first on PATH so it wins over real curl/gh.
  BIN="$ROOT/bin"; mkdir -p "$BIN"
  CALLS="$ROOT/gh-calls.log"; : > "$CALLS"

  cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
# Ignore all args/stdin; emit a canned Gemini response with usageMetadata so the
# cost-audit path is exercised (1000 prompt + 100 output = 1100 total tokens).
bullets="\${STUB_BULLETS:-- did a concrete thing in foo.py:10}"
jq -n --arg t "\$bullets" \\
  '{candidates:[{content:{parts:[{text:\$t}]}}],
    usageMetadata:{promptTokenCount:1000, candidatesTokenCount:100, totalTokenCount:1100}}'
EOF
  chmod +x "$BIN/curl"

  cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$CALLS"
# 'pr view' returns nonzero (no existing PR) so the script takes the create path.
case "\$1 \$2" in
  "pr view") exit 1 ;;
  "pr create") cat >/dev/null; echo "https://example/pr/1"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$BIN/gh"
  export PATH="$BIN:$PATH"

  # Work-session fixture. WORK_ROOT is fixed so the encoded project-dir prefix
  # is predictable regardless of the temp HOME path.
  export SESSION_LOG_WORK_ROOT="/Users/tester/work"
  local proj="$HOME/.claude/projects/-Users-tester-work-demo"
  mkdir -p "$proj"
  SESSION="$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  cat > "$SESSION" <<'EOF'
{"type":"user","message":{"role":"user","content":"please fix the parser"},"cwd":"/Users/tester/work/demo","timestamp":"2026-08-27T09:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","text":"secret internal reasoning"},{"type":"text","text":"Fixed it in parser.py:12"}]}}
EOF

  # Notes repo with a committed weekly note + a local bare "origin".
  ORIGIN="$ROOT/origin.git"; git init --quiet --bare "$ORIGIN"
  NOTES="$ROOT/notes"; git init --quiet "$NOTES"
  git -C "$NOTES" config user.email t@t.test
  git -C "$NOTES" config user.name tester
  mkdir -p "$NOTES/NUS-Enterprise/Weekly"
  printf '# Week 35\n' > "$NOTES/NUS-Enterprise/Weekly/2026-W35.md"
  git -C "$NOTES" add -A
  git -C "$NOTES" commit --quiet -m init
  git -C "$NOTES" branch -M main
  git -C "$NOTES" remote add origin "$ORIGIN"
  git -C "$NOTES" push --quiet -u origin main
  git -C "$NOTES" remote set-head origin main
  export SESSION_LOG_NOTES_REPO="$NOTES"

  # Auth + isolation from the real ~/work/dotfiles/.env.
  export GEMINI_API_KEY="test-key"
  export SESSION_LOG_ENV="$ROOT/nonexistent.env"
  export TZ=UTC
}

teardown() { rm -rf "$ROOT"; }

@test "dry run: summarizes the session but never pushes or opens a PR" {
  run env SESSION_LOG_DRY_RUN=1 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"found 1 work session"* ]]
  [[ "$output" == *"summarizing aaaaaaaa"* ]]
  [[ "$output" == *"DRY RUN"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]                 # gh never called
  run git -C "$SESSION_LOG_NOTES_REPO" branch --list "auto/session-log-*"
  [ -z "$output" ]                              # no branch left behind (worktree cleaned)
}

@test "real run: commits the entry directly to the base branch on origin (no PR)" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done: logged"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]                 # gh never called; no PR

  # No dated branch is created; the commit lands straight on origin/main.
  run git -C "$SESSION_LOG_NOTES_REPO" branch -r --list "origin/auto/session-log-*"
  [ -z "$output" ]

  local note
  note="$(git -C "$SESSION_LOG_NOTES_REPO" show "origin/main:NUS-Enterprise/Weekly/2026-W35.md")"
  [[ "$note" == *"## Session log —"* ]]
  [[ "$note" == *"did a concrete thing in foo.py:10"* ]]
  [[ "$note" == *"auto-session-log aaaaaaaa-1111-2222-3333-444444444444"* ]]
  # Thinking text must not leak into the note (only the assistant 'text' block is sent).
  [[ "$note" != *"secret internal reasoning"* ]]
}

@test "watermark advances so a second run finds nothing new" {
  run bash "$SCRIPT"; [ "$status" -eq 0 ]
  : > "$ROOT/gh-calls.log"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no work sessions since last run"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]
}

@test "dedup: reprocessing the same session the same day makes no commit" {
  run bash "$SCRIPT"; [ "$status" -eq 0 ]
  # Force re-selection: drop the watermark and bump the session mtime.
  rm -f "$HOME/.claude/.daily-session-log.watermark"
  touch "$SESSION"
  : > "$ROOT/gh-calls.log"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to commit"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]
}

@test "missing GEMINI_API_KEY fails fast with a clear message" {
  unset GEMINI_API_KEY
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GEMINI_API_KEY not set"* ]]
}

@test "a session with no loggable work is skipped (no commit)" {
  export STUB_BULLETS="- (no substantive work)"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no loggable work"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]
}

@test "records a per-call cost line (session id + tokens) in the notes repo" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local costlog="$SESSION_LOG_NOTES_REPO/logs/session-log-costs.jsonl"
  [ -f "$costlog" ]
  run jq -rs '[.[] | select(.type=="call")] | length' "$costlog"
  [ "$output" = "1" ]
  run jq -r 'select(.type=="call") | "\(.session) \(.input_tokens) \(.output_tokens) \(.logged)"' "$costlog"
  [ "$output" = "aaaaaaaa-1111-2222-3333-444444444444 1000 100 true" ]
}

@test "records a run-summary cost line with the aggregate estimate" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local costlog="$SESSION_LOG_NOTES_REPO/logs/session-log-costs.jsonl"
  # 1000 in × $0.10/M + 100 out × $0.40/M = 0.000140 (calc_cost uses %.6f)
  run jq -r 'select(.type=="run") | "\(.api_calls) \(.total_tokens) \(.est_cost_usd)"' "$costlog"
  [ "$output" = "1 1100 0.000140" ]
}

@test "still records cost for a call that produced no loggable work" {
  export STUB_BULLETS="- (no substantive work)"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local costlog="$SESSION_LOG_NOTES_REPO/logs/session-log-costs.jsonl"
  run jq -r 'select(.type=="call") | .logged' "$costlog"
  [ "$output" = "false" ]
  run jq -r 'select(.type=="run") | "\(.api_calls) \(.sessions_logged)"' "$costlog"
  [ "$output" = "1 0" ]
}
