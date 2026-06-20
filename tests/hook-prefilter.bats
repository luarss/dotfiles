#!/usr/bin/env bats
# Tests for the fast pre-filter optimisation in db-guard, db-rate-limit, and
# symlink-memory hooks.
#
# Strategy: replace jq with a stub that writes a sentinel file when invoked.
# Non-matching payloads must exit 0 WITHOUT touching the sentinel (pre-filter
# fired). Matching payloads must touch the sentinel (pre-filter passed through).

HOOKS="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.claude/hooks"

setup() {
  WORKDIR="$(mktemp -d)"

  # jq stub: records invocation, then delegates to the real jq so the hook
  # can still parse the payload on the hot path.
  REAL_JQ="$(command -v jq)"
  JQ_STUB="$WORKDIR/jq"
  cat > "$JQ_STUB" <<EOF
#!/usr/bin/env bash
touch "$WORKDIR/jq_called"
exec "$REAL_JQ" "\$@"
EOF
  chmod +x "$JQ_STUB"

  # Prepend our stub dir so hooks pick it up.
  export PATH="$WORKDIR:$PATH"

  # Silence symlink-memory side-effects: point its Obsidian target somewhere
  # harmless (it will still exit early via the pre-filter or regex guard).
  export HOME="$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

# ─── helpers ────────────────────────────────────────────────────────────────

bash_payload() {
  # Build a Bash PreToolUse payload without using jq (avoids touching sentinel).
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' \
    "$(printf '%s' "$cmd" | sed 's/"/\\"/g')"
}

mcp_payload() {
  local tool="$1"
  printf '{"tool_name":"%s","tool_input":{}}' "$tool"
}

write_payload() {
  local path="$1"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"/project"}' \
    "$(printf '%s' "$path" | sed 's/"/\\"/g')"
}

jq_was_called()    { [[ -f "$WORKDIR/jq_called" ]]; }
jq_was_not_called() { [[ ! -f "$WORKDIR/jq_called" ]]; }
reset_sentinel()   { rm -f "$WORKDIR/jq_called"; }

run_hook() {
  local hook="$1" payload="$2"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$hook"
}

# ─── db-guard: pre-filter ───────────────────────────────────────────────────

@test "db-guard: irrelevant Bash payload exits 0 without calling jq" {
  run_hook "$HOOKS/db-guard.sh" "$(bash_payload "git status")"
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "db-guard: Write tool payload (no SQL keyword) exits 0 without calling jq" {
  run_hook "$HOOKS/db-guard.sh" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt"}}'
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "db-guard: payload containing 'mysql' passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-guard.sh" "$(bash_payload "echo mysql")"
  [ "$status" -eq 0 ]
  jq_was_called
}

@test "db-guard: payload containing 'psql' passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-guard.sh" "$(bash_payload "echo psql")"
  [ "$status" -eq 0 ]
  jq_was_called
}

@test "db-guard: payload containing 'mariadb' passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-guard.sh" "$(bash_payload "echo mariadb")"
  [ "$status" -eq 0 ]
  jq_was_called
}

# ─── db-rate-limit: pre-filter ──────────────────────────────────────────────

@test "db-rate-limit: irrelevant Bash payload exits 0 without calling jq" {
  run_hook "$HOOKS/db-rate-limit.sh" "$(bash_payload "ls -la")"
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "db-rate-limit: MCP tool without mysql exits 0 without calling jq" {
  run_hook "$HOOKS/db-rate-limit.sh" "$(mcp_payload "mcp__postgres__query")"
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "db-rate-limit: payload containing 'mysql' passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-rate-limit.sh" "$(bash_payload "echo mysql")"
  [ "$status" -eq 0 ]
  jq_was_called
}

@test "db-rate-limit: payload containing 'mariadb' passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-rate-limit.sh" "$(bash_payload "echo mariadb")"
  [ "$status" -eq 0 ]
  jq_was_called
}

@test "db-rate-limit: MCP mysql tool name passes through pre-filter and calls jq" {
  run_hook "$HOOKS/db-rate-limit.sh" "$(mcp_payload "mcp__mysql__query")"
  [ "$status" -eq 0 ]
  jq_was_called
}

# ─── symlink-memory: pre-filter ─────────────────────────────────────────────

@test "symlink-memory: Write to non-memory path exits 0 without calling jq" {
  run_hook "$HOOKS/symlink-memory.sh" \
    "$(write_payload "/Users/user/.claude/settings.json")"
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "symlink-memory: Edit to a docs path exits 0 without calling jq" {
  run_hook "$HOOKS/symlink-memory.sh" \
    "$(write_payload "/Users/user/projects/dotfiles/README.md")"
  [ "$status" -eq 0 ]
  jq_was_not_called
}

@test "symlink-memory: Write to a /memory/ path passes through pre-filter and calls jq" {
  run_hook "$HOOKS/symlink-memory.sh" \
    "$(write_payload "/Users/user/.claude/projects/-Users-user-project/memory/note.md")"
  # Hook may exit non-zero (missing Obsidian index is fine); we only check jq ran.
  jq_was_called
}

# ─── combined throughput sanity ──────────────────────────────────────────────
# 50 irrelevant Bash calls through db-guard must complete in under 5 seconds.
# This is a loose budget — the real saving is ~25ms/call avoided; even on slow
# CI, 50 pure-bash pre-filter exits should finish well within 2s.

@test "db-guard: 50 irrelevant calls complete in under 5 seconds" {
  local start end elapsed
  ms() { python3 -c "import time; print(int(time.time()*1000))"; }
  start=$(ms)
  for i in $(seq 1 50); do
    bash_payload "git log --oneline -10" | bash "$HOOKS/db-guard.sh" >/dev/null 2>&1
  done
  end=$(ms)
  elapsed=$(( end - start ))
  [ "$elapsed" -lt 5000 ]
}
