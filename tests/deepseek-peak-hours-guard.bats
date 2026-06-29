#!/usr/bin/env bats
# Tests for .claude/hooks/deepseek-peak-hours-guard.sh
#
# Strategy: stub `date` via PATH prepending so tests can control the apparent
# UTC hour without waiting for a real clock. STUB_HOUR (0-23) drives the stub;
# defaults to 12 (off-peak) so tests that don't set it pass through freely.

HOOK="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.claude/hooks/deepseek-peak-hours-guard.sh"
DEEPSEEK_URL="https://api.deepseek.com/anthropic"

setup() {
  WORKDIR="$(mktemp -d)"

  # date stub: intercepts -u +%H and -u +%H:%M; delegates everything else.
  DATE_STUB="$WORKDIR/date"
  cat > "$DATE_STUB" <<'EOF'
#!/usr/bin/env bash
hour="${STUB_HOUR:-12}"
args="$*"
case "$args" in
  *+%H)    printf '%02d\n' "$hour" ;;
  *+%H:%M) printf '%02d:00\n' "$hour" ;;
  *)       exec /bin/date "$@" ;;
esac
EOF
  chmod +x "$DATE_STUB"
  export PATH="$WORKDIR:$PATH"
}

teardown() {
  rm -rf "$WORKDIR"
}

run_hook() {
  run bash "$HOOK"
}

# ─── profile gate ────────────────────────────────────────────────────────────

@test "no-op when ANTHROPIC_BASE_URL is unset" {
  unset ANTHROPIC_BASE_URL
  export STUB_HOUR=2   # would block on DeepSeek
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when ANTHROPIC_BASE_URL is a non-DeepSeek provider" {
  export ANTHROPIC_BASE_URL="https://api.anthropic.com"
  export STUB_HOUR=2
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when ANTHROPIC_BASE_URL is Mimo (third-party, non-DeepSeek)" {
  export ANTHROPIC_BASE_URL="https://api.xiaomimimo.com/anthropic"
  export STUB_HOUR=15
  run_hook
  [ "$status" -eq 0 ]
}

# ─── off-peak hours (allowed) ────────────────────────────────────────────────

@test "DeepSeek: hour 0 (midnight) is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=0
  run_hook
  [ "$status" -eq 0 ]
}

@test "DeepSeek: hour 4 (boundary, exclusive) is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=4
  run_hook
  [ "$status" -eq 0 ]
}

@test "DeepSeek: hour 12 (midday) is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=12
  run_hook
  [ "$status" -eq 0 ]
}

@test "DeepSeek: hour 13 is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=13
  run_hook
  [ "$status" -eq 0 ]
}

@test "DeepSeek: hour 18 (boundary, exclusive) is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=18
  run_hook
  [ "$status" -eq 0 ]
}

@test "DeepSeek: hour 23 is off-peak and allowed" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=23
  run_hook
  [ "$status" -eq 0 ]
}

# ─── peak window 01:00–04:00 UTC (blocked) ───────────────────────────────────

@test "DeepSeek: hour 1 (start of morning window) is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=1
  run_hook
  [ "$status" -eq 2 ]
}

@test "DeepSeek: hour 2 is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=2
  run_hook
  [ "$status" -eq 2 ]
}

@test "DeepSeek: hour 3 (last hour of morning window) is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=3
  run_hook
  [ "$status" -eq 2 ]
}

# ─── peak window 14:00–18:00 UTC (blocked) ───────────────────────────────────

@test "DeepSeek: hour 14 (start of afternoon window) is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=14
  run_hook
  [ "$status" -eq 2 ]
}

@test "DeepSeek: hour 16 is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=16
  run_hook
  [ "$status" -eq 2 ]
}

@test "DeepSeek: hour 17 (last hour of afternoon window) is blocked" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=17
  run_hook
  [ "$status" -eq 2 ]
}

# ─── error message quality ───────────────────────────────────────────────────

@test "block message includes current UTC time" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=2
  run_hook
  [ "$status" -eq 2 ]
  [[ "$output" == *"02:00"* ]]
}

@test "block message mentions peak-hour windows" {
  export ANTHROPIC_BASE_URL="$DEEPSEEK_URL"
  export STUB_HOUR=15
  run_hook
  [ "$status" -eq 2 ]
  [[ "$output" == *"01:00"* ]] && [[ "$output" == *"14:00"* ]]
}
