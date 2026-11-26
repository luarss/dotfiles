#!/usr/bin/env bats
# Tests for scripts/daily-session-log.sh
#
# All external services are stubbed so these run offline:
#   - agy   -> a stub that emits a canned `agy --print` JSON response
#              (bullets from $STUB_BULLETS, default one concrete bullet;
#              $STUB_STATUS/$STUB_ERROR drive the error path).
#   - gh    -> a stub that records `pr create`/`pr view` calls to a file.
#   - git   -> real; pushes go to a local bare "origin", so the full
#              worktree/commit/push path exercises without network.
#
# HOME is redirected to a temp dir so the watermark/lock/projects live there.
# The script's env knobs (SESSION_LOG_*) point discovery + notes repo at
# fixtures we build in setup.

setup_file() {
  export SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/daily-session-log.sh"
  export TEMPLATE_ROOT="$(mktemp -d)"

  # Shared stub bin dir, put first on PATH so it wins over real agy/gh.
  export SHARED_BIN="$TEMPLATE_ROOT/bin"
  mkdir -p "$SHARED_BIN"

  cat > "$SHARED_BIN/agy" <<'EOF'
#!/usr/bin/env bash
# Ignore all args; emit a canned `agy --print` JSON response with a usage block so
# the cost-audit path is exercised (1000 input + 100 output = 1100 total tokens).
# STUB_STATUS=ERROR (with STUB_ERROR) exercises the error/skip path.
bullets="${STUB_BULLETS:-- did a concrete thing in foo.py:10}"
status="${STUB_STATUS:-SUCCESS}"
if [ "$status" = "SUCCESS" ]; then
  case "$bullets" in
    *\"*|*\\*|*$'\n'*)
      jq -nc --arg t "$bullets" \
        '{conversation_id:"c1", status:"SUCCESS", response:$t, error:"",
          usage:{input_tokens:1000, output_tokens:100, thinking_tokens:0, cache_read_tokens:0, total_tokens:1100}}'
      ;;
    *)
      printf '{"conversation_id":"c1","status":"SUCCESS","response":"%s","error":"","usage":{"input_tokens":1000,"output_tokens":100,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":1100}}\n' "$bullets"
      ;;
  esac
else
  err="${STUB_ERROR:-boom}"
  case "$err" in
    *\"*|*\\*|*$'\n'*)
      jq -nc --arg e "$err" \
        '{conversation_id:"", status:"ERROR", response:"", error:$e,
          usage:{input_tokens:0, output_tokens:0, thinking_tokens:0, cache_read_tokens:0, total_tokens:0}}'
      ;;
    *)
      printf '{"conversation_id":"","status":"ERROR","response":"","error":"%s","usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0}}\n' "$err"
      ;;
  esac
fi
EOF
  chmod +x "$SHARED_BIN/agy"

  cat > "$SHARED_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_CALLS_LOG"
# 'pr view' returns nonzero (no existing PR) so the script takes the create path.
case "$1 $2" in
  "pr view") exit 1 ;;
  "pr create") cat >/dev/null; echo "https://example/pr/1"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$SHARED_BIN/gh"

  # Template fixture tree copied into each test's fresh ROOT.
  local tpl="$TEMPLATE_ROOT/tpl"
  local proj="$tpl/home/.claude/projects/-Users-tester-work-demo"
  mkdir -p "$proj"
  cat > "$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"please fix the parser"},"cwd":"/Users/tester/work/demo","timestamp":"2026-08-27T09:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","text":"secret internal reasoning"},{"type":"text","text":"Fixed it in parser.py:12"}]}}
EOF

  # Notes repo with a committed weekly note + a local bare "origin".
  local origin="$tpl/origin.git"; git init --quiet --bare "$origin"
  local notes="$tpl/notes"; git init --quiet "$notes"
  git -C "$notes" config user.email t@t.test
  git -C "$notes" config user.name tester
  mkdir -p "$notes/NUS-Enterprise/Weekly"
  printf '# Week 35\n' > "$notes/NUS-Enterprise/Weekly/2026-W35.md"
  git -C "$notes" add -A
  git -C "$notes" commit --quiet -m init
  git -C "$notes" branch -M main
  git -C "$notes" remote add origin "$origin"
  git -C "$notes" push --quiet -u origin main
  git -C "$notes" remote set-head origin main

  export PATH="$SHARED_BIN:$PATH"
  export SESSION_LOG_WORK_ROOT="/Users/tester/work"
  export TZ=UTC
}

teardown_file() { rm -rf "$TEMPLATE_ROOT"; }

setup() {
  ROOT="$(mktemp -d)"
  cp -R "$TEMPLATE_ROOT/tpl/." "$ROOT/"
  export HOME="$ROOT/home"
  export GH_CALLS_LOG="$ROOT/gh-calls.log"
  : > "$GH_CALLS_LOG"
  SESSION="$HOME/.claude/projects/-Users-tester-work-demo/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  ORIGIN="$ROOT/origin.git"
  NOTES="$ROOT/notes"
  git -C "$NOTES" remote set-url origin "$ORIGIN"
  export SESSION_LOG_NOTES_REPO="$NOTES"
  # Isolate from the real ~/work/dotfiles/.env (agy uses its own cached auth).
  export SESSION_LOG_ENV="$ROOT/nonexistent.env"
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

@test "an agy error is skipped (no commit) but still records a cost line" {
  export STUB_STATUS=ERROR
  export STUB_ERROR="model unavailable"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy returned no summary"* ]]
  [[ "$output" == *"model unavailable"* ]]
  [ ! -s "$ROOT/gh-calls.log" ]
  local costlog="$SESSION_LOG_NOTES_REPO/logs/session-log-costs.jsonl"
  run jq -r 'select(.type=="call") | "\(.logged) \(.error)"' "$costlog"
  [ "$output" = "false model unavailable" ]
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
