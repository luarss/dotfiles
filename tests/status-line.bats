#!/usr/bin/env bats
# Tests for status-line.sh: subscription-usage segment, rate-limit reset times,
# and width-aware (COLUMNS) degradation.
#
# Strategy: feed the script a synthetic stdin JSON (no transcript → zero tokens,
# a non-git temp cwd → no git segment) so the only variable parts are the model
# name, the usage segment, and the terminal width. Then assert on the rendered
# text and its visible length.

shopt -s extglob

SL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/status-line.sh"

setup_file() {
  export WORKDIR="$(mktemp -d)"
  # A fixed-name, non-git directory so DIR == "proj" and get_git_info stays empty.
  export DIRPATH="$WORKDIR/proj"
  mkdir -p "$DIRPATH"
  export TRANSCRIPT="$WORKDIR/transcript.jsonl"
  printf '%s\n' '{"usage":{"input_tokens":258000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":100}}' > "$TRANSCRIPT"
  export NOW="$(date +%s)"
}

teardown_file() {
  rm -rf "$WORKDIR"
}

setup() {
  USAGE_CACHE="$WORKDIR/usage-${BATS_TEST_NUMBER}.json"
  RESPONSE_FILE="$WORKDIR/response-${BATS_TEST_NUMBER}.json"
  CALLED_FILE="$WORKDIR/called-${BATS_TEST_NUMBER}"
  FETCH_CMD=""
}

# ─── helpers ──────────────────────────────────────────────────────────────────

# Run the status line at a given width. $1=COLUMNS $2=JSON $3=SHOW_USAGE_LIMITS(=1)
sl() {
  local cols="$1" json="$2" show="${3-1}"
  COLUMNS="$cols" SHOW_USAGE_LIMITS="$show" \
    CLAUDE_USAGE_CACHE="$USAGE_CACHE" CLAUDE_USAGE_FETCH_CMD="${FETCH_CMD:-false}" \
    bash "$SL" <<< "$json"
}

strip_ansi() {
  printf '%s' "${1//$'\033'\[*([0-9;])m/}"
}

# Visible (display-cell) length, mirroring the script's own visible_len: strip
# ANSI, count code points, add 1 per double-width glyph.
vislen() {
  local s nw wide
  s="${1//$'\033'\[*([0-9;])m/}"
  nw="${s//➜/}"
  nw="${nw//⏱/}"
  nw="${nw//⏳/}"
  nw="${nw//⚡/}"
  nw="${nw//⚠/}"
  wide=$(( ${#s} - ${#nw} ))
  printf '%s' "$(( ${#s} + wide ))"
}

now() { printf '%s' "$NOW"; }

touch_stamp() {
  date -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$1" +%Y%m%d%H%M.%S
}

main_line() { printf '%s\n' "${1%%$'\n'*}"; }
usage_line() { [[ "$1" == *$'\n'* ]] && printf '%s\n' "${1#*$'\n'}"; }

widest_line() {
  local line widest=0 len
  while IFS= read -r line; do
    len=$(vislen "$line")
    [ "$len" -gt "$widest" ] && widest=$len
  done <<< "$1"
  printf '%s' "$widest"
}

# JSON with only the five_hour window. $1=used_percentage $2=resets_at (epoch).
json_5h() {
  printf '{"model":{"display_name":"Test","id":"test-model"},"workspace":{"current_dir":"%s"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s}}}\n' \
    "$DIRPATH" "$1" "$2"
}

# JSON with both windows. $1=p5 $2=r5 $3=p7 $4=r7
json_both() {
  printf '{"model":{"display_name":"Test","id":"test-model"},"workspace":{"current_dir":"%s"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}\n' \
    "$DIRPATH" "$1" "$2" "$3" "$4"
}

# JSON with no rate_limits at all (third-party providers).
json_none() {
  printf '{"model":{"display_name":"Test","id":"test-model"},"workspace":{"current_dir":"%s"}}\n' "$DIRPATH"
}

# ─── gating ─────────────────────────────────────────────────────────────────

@test "usage segment hidden when SHOW_USAGE_LIMITS != 1" {
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" 0)
  [[ "$out" != *"⏳"* ]]
  [[ "$out" != *"5h"* ]]
}

@test "usage segment hidden when no rate_limits present (even with flag on)" {
  out=$(sl 300 "$(json_none)" 1)
  [[ "$out" != *"⏳"* ]]
  [[ "$out" != *"5h"* ]]
}

@test "usage segment shown when flag on and rate_limits present" {
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" 1)
  [[ "$out" == *"⏳"* ]]
  [[ "$out" == *"5h"* ]]
  [[ "$out" == *"7d"* ]]
}

# ─── reset-time formatting (full mode, huge width) ────────────────────────────

@test "reset time formats as Hh Mm for an in-hour window" {
  # 2h13m out (+20s buffer so a slow run still rounds to 13m)
  out=$(sl 300 "$(json_5h 36 "$(( $(now) + 8000 ))")")
  [[ "$out" == *"(resets 2h13m)"* ]]
}

@test "reset time formats as minutes only when under an hour" {
  out=$(sl 300 "$(json_5h 36 "$(( $(now) + 860 ))")")
  [[ "$out" == *"(resets 14m)"* ]]
}

@test "reset time formats as Dd Hh for a multi-day window" {
  # 2d3h out
  out=$(sl 300 "$(json_5h 18 "$(( $(now) + 184200 ))")")
  [[ "$out" == *"(resets 2d3h)"* ]]
}

@test "no reset string when the window already reset (past timestamp)" {
  out=$(sl 300 "$(json_5h 36 "$(( $(now) - 100 ))")")
  [[ "$out" == *"5h"* ]]
  [[ "$out" != *"resets"* ]]
}

# ─── colour by threshold ──────────────────────────────────────────────────────

@test "usage percentage turns red past the critical threshold" {
  # 95% >= USAGE_CRIT_PCT (90) → red (\033[0;31m) precedes "95%"
  out=$(sl 300 "$(json_5h 95 "$(( $(now) + 8000 ))")")
  [[ "$out" == *$'\033[0;31m'"95%"* ]]
}

# ─── width-aware degradation ──────────────────────────────────────────────────

@test "usage renders on its own second line" {
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")")
  [[ "$(main_line "$out")" != *"⏳"* ]]
  [[ "$(usage_line "$out")" == *"⏳"* ]]
}

@test "main line has no trailing newline when usage is hidden" {
  out=$(sl 300 "$(json_none)" 1)
  [ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = "0" ]
}

@test "full form at a wide terminal includes reset times without limit labels" {
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")")
  line=$(usage_line "$out")
  [[ "$line" == *"5h"* ]]
  [[ "$line" == *"(resets 2h13m)"* ]]
  [[ "$line" == *"·"* ]]
  [[ "$line" != *"limit"* ]]
  [[ "$line" != *"usage:"* ]]
}

@test "falls back to compact form when full does not fit" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  full_len=$(vislen "$(usage_line "$(sl 9999 "$json")")")
  out=$(usage_line "$(sl "$(( full_len - 1 ))" "$json")")
  [[ "$out" == *"⏳"* ]]
  [[ "$out" == *"5h"* ]]
  [[ "$out" != *"resets"* ]]
  [ "$(vislen "$out")" -le "$(( full_len - 1 ))" ]
}

@test "drops usage line when even compact does not fit" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  full_len=$(vislen "$(usage_line "$(sl 9999 "$json")")")
  compact_len=$(vislen "$(usage_line "$(sl "$(( full_len - 1 ))" "$json")")")
  out=$(sl "$(( compact_len - 1 ))" "$json")
  [[ "$out" != *"⏳"* ]]
  [[ "$out" == *"proj"* ]]
  [[ "$out" == *"Test"* ]]
}

@test "no rendered line exceeds COLUMNS across a range of widths" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  for cols in 200 130 100 80; do
    out=$(sl "$cols" "$json")
    len=$(widest_line "$out")
    [ "$len" -le "$cols" ] || {
      echo "width $cols overflowed: visible len $len" >&2
      return 1
    }
  done
}

# ─── context-window detection ─────────────────────────────────────────────────
#
# 258k input tokens is 25.8% of a 1M window and 129.0% of a 200k one, so the
# rendered percentage tells us which CTX_LIMIT the script picked.

# JSON naming a specific model id, pointed at a 258k-token transcript.
json_model() {
  printf '{"model":{"display_name":"Test","id":"%s"},"workspace":{"current_dir":"%s"},"transcript_path":"%s"}\n' \
    "$1" "$DIRPATH" "$TRANSCRIPT"
}

@test "1M-context models render 258k as 25.8%" {
  for id in claude-opus-5 claude-sonnet-5 claude-fable-5 claude-mythos-5 \
            claude-opus-4-8 claude-opus-4-7 claude-opus-4-6 claude-sonnet-4-6 \
            'claude-sonnet-4-5[1m]'; do
    out=$(sl 300 "$(json_model "$id")" 0)
    [[ "$out" == *"25.8%"* ]] || {
      echo "$id did not resolve to a 1M context window: $out" >&2
      return 1
    }
  done
}

@test "200k-context models render 258k as over 100%" {
  for id in claude-haiku-4-5-20251001 claude-opus-4-5 claude-sonnet-4-5; do
    out=$(sl 300 "$(json_model "$id")" 0)
    [[ "$out" == *"129.0%"* ]] || {
      echo "$id did not resolve to a 200k context window: $out" >&2
      return 1
    }
  done
}

@test "models.json lookup wins for third-party 1M models" {
  out=$(sl 300 "$(json_model deepseek-v4-pro)" 0)
  [[ "$out" == *"25.8%"* ]]
}

# ─── core line always present ─────────────────────────────────────────────────

@test "core segments render regardless of usage settings" {
  out=$(sl 300 "$(json_none)" 0)
  [[ "$out" == *"proj"* ]]      # cwd basename
  [[ "$out" == *"Test"* ]]      # model display name
  [[ "$out" == *"⏱"* ]]         # session duration glyph
}

# ─── model-scoped weekly limits (Fable) ─────────────────────────────────────

usage_response() {
  local resets="${2:-2030-01-01T00:00:00.123+00:00}"
  printf '{"limits":[{"kind":"weekly_all","percent":53,"resets_at":"2030-01-01T00:00:00.123+00:00","scope":null},{"kind":"weekly_scoped","percent":%s,"resets_at":"%s","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}]}\n' \
    "$1" "$resets"
}

stub_fetch() {
  usage_response "$1" > "$RESPONSE_FILE"
  FETCH_CMD="cat '$RESPONSE_FILE'"
}

@test "Fable limit fetched on first render when cache is missing" {
  stub_fetch 9
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  [[ "$(usage_line "$out")" == *"Fable"*"9%"* ]]
  [ -f "$USAGE_CACHE" ]
}

@test "Fable limit shown in compact form" {
  stub_fetch 9
  out=$(sl 40 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  plain=$(strip_ansi "$out")
  [[ "$plain" == *"Fable 9%"* ]]
  [[ "$plain" != *"resets"* ]]
}

@test "fresh cache is used without fetching" {
  usage_response 42 > "$USAGE_CACHE"
  FETCH_CMD="echo fetched > '$CALLED_FILE'; false"
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  [[ "$out" == *"42%"* ]]
  [ ! -f "$CALLED_FILE" ]
}

@test "Fable limit hidden when SHOW_USAGE_LIMITS != 1" {
  stub_fetch 9
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" 0)
  [[ "$out" != *"Fable"* ]]
  [ ! -f "$USAGE_CACHE" ]
}

@test "usage endpoint not called for sessions without rate_limits" {
  stub_fetch 9
  out=$(sl 300 "$(json_none)" 1)
  [[ "$out" != *"Fable"* ]]
  [ ! -f "$USAGE_CACHE" ]
}

@test "failed fetch renders without Fable and caches an empty placeholder" {
  FETCH_CMD="false"
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  [[ "$out" == *"5h"* ]]
  [[ "$out" != *"Fable"* ]]
  [ "$(cat "$USAGE_CACHE")" = "{}" ]
}

@test "malformed response is not cached" {
  FETCH_CMD="echo not-json"
  sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" >/dev/null
  [ "$(cat "$USAGE_CACHE")" = "{}" ]
}

@test "Fable limit hidden once cached reset time has passed" {
  usage_response 14 "2020-01-01T00:00:00.123+00:00" > "$USAGE_CACHE"
  FETCH_CMD="false"
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  [[ "$out" == *"7d"* ]]
  [[ "$out" != *"Fable"* ]]
}

@test "failed fetch increments the failure count" {
  FETCH_CMD="false"
  sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" >/dev/null
  [ "$(cat "$USAGE_CACHE.failures")" = "1" ]
}

@test "successful fetch clears the failure count" {
  echo 3 > "$USAGE_CACHE.failures"
  stub_fetch 9
  sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" >/dev/null
  [ ! -f "$USAGE_CACHE.failures" ]
}

@test "stale cache is not refreshed while backing off after failures" {
  usage_response 42 > "$USAGE_CACHE"
  touch -t "$(touch_stamp $(( $(now) - 400 )))" "$USAGE_CACHE"
  echo 2 > "$USAGE_CACHE.failures"
  FETCH_CMD="echo fetched > '$CALLED_FILE'; false"
  sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" >/dev/null
  sleep 0.2
  [ ! -f "$CALLED_FILE" ]
}

@test "Fable reset shown in full form" {
  stub_fetch 9
  plain=$(strip_ansi "$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")")
  [[ "$(usage_line "$plain")" == *"Fable 9% (resets "* ]]
}
