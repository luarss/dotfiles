#!/usr/bin/env bats
# Tests for status-line.sh: subscription-usage segment, rate-limit reset times,
# and width-aware (COLUMNS) degradation.
#
# Strategy: feed the script a synthetic stdin JSON (no transcript → zero tokens,
# a non-git temp cwd → no git segment) so the only variable parts are the model
# name, the usage segment, and the terminal width. Then assert on the rendered
# text and its visible length.

SL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/status-line.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  # A fixed-name, non-git directory so DIR == "proj" and get_git_info stays empty.
  DIRPATH="$WORKDIR/proj"
  mkdir -p "$DIRPATH"
  USAGE_CACHE="$WORKDIR/usage.json"
  FETCH_CMD=""
}

teardown() {
  rm -rf "$WORKDIR"
}

# ─── helpers ──────────────────────────────────────────────────────────────────

# Run the status line at a given width. $1=COLUMNS $2=JSON $3=SHOW_USAGE_LIMITS(=1)
sl() {
  local cols="$1" json="$2" show="${3-1}"
  COLUMNS="$cols" SHOW_USAGE_LIMITS="$show" \
    CLAUDE_USAGE_CACHE="$USAGE_CACHE" CLAUDE_USAGE_FETCH_CMD="${FETCH_CMD:-false}" \
    bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$SL"
}

# Visible (display-cell) length, mirroring the script's own visible_len: strip
# ANSI, count code points, add 1 per double-width glyph.
vislen() {
  local s wide
  s=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g')
  wide=$(printf '%s' "$s" | grep -oE '➜|⏱|⏳|⚡|⚠' | grep -c .)
  printf '%s' "$(( ${#s} + wide ))"
}

now() { date +%s; }

touch_stamp() {
  date -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$1" +%Y%m%d%H%M.%S
}

main_line() { printf '%s\n' "$1" | sed -n 1p; }
usage_line() { printf '%s\n' "$1" | sed -n 2p; }

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
  jq -n --arg dir "$DIRPATH" --argjson p "$1" --argjson r "$2" \
    '{model:{display_name:"Test",id:"test-model"},
      workspace:{current_dir:$dir},
      rate_limits:{five_hour:{used_percentage:$p,resets_at:$r}}}'
}

# JSON with both windows. $1=p5 $2=r5 $3=p7 $4=r7
json_both() {
  jq -n --arg dir "$DIRPATH" \
    --argjson p5 "$1" --argjson r5 "$2" --argjson p7 "$3" --argjson r7 "$4" \
    '{model:{display_name:"Test",id:"test-model"},
      workspace:{current_dir:$dir},
      rate_limits:{five_hour:{used_percentage:$p5,resets_at:$r5},
                   seven_day:{used_percentage:$p7,resets_at:$r7}}}'
}

# JSON with no rate_limits at all (third-party providers).
json_none() {
  jq -n --arg dir "$DIRPATH" \
    '{model:{display_name:"Test",id:"test-model"},workspace:{current_dir:$dir}}'
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
  local transcript="$WORKDIR/transcript.jsonl"
  printf '%s\n' '{"usage":{"input_tokens":258000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":100}}' > "$transcript"
  jq -n --arg dir "$DIRPATH" --arg id "$1" --arg t "$transcript" \
    '{model:{display_name:"Test",id:$id},
      workspace:{current_dir:$dir},
      transcript_path:$t}'
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
  jq -n --argjson pct "$1" \
    '{limits:[
       {kind:"weekly_all",percent:53,resets_at:"2030-01-01T00:00:00.123+00:00",scope:null},
       {kind:"weekly_scoped",percent:$pct,resets_at:"2030-01-01T00:00:00.123+00:00",
        scope:{model:{id:null,display_name:"Fable"},surface:null}}]}'
}

stub_fetch() {
  usage_response "$1" > "$WORKDIR/response.json"
  FETCH_CMD="cat '$WORKDIR/response.json'"
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
  plain=$(printf '%s' "$out" | sed -E $'s/\033\\[[0-9;]*m//g')
  [[ "$plain" == *"Fable 9%"* ]]
  [[ "$plain" != *"resets"* ]]
}

@test "fresh cache is used without fetching" {
  usage_response 42 > "$USAGE_CACHE"
  FETCH_CMD="echo fetched > '$WORKDIR/called'; false"
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")")
  [[ "$out" == *"42%"* ]]
  [ ! -f "$WORKDIR/called" ]
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
  usage_response 14 | jq '.limits[1].resets_at = "2020-01-01T00:00:00.123+00:00"' > "$USAGE_CACHE"
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
  FETCH_CMD="echo fetched > '$WORKDIR/called'; false"
  sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" >/dev/null
  sleep 0.2
  [ ! -f "$WORKDIR/called" ]
}

@test "Fable reset shown in full form" {
  stub_fetch 9
  plain=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 185000 ))")" | sed -E $'s/\033\\[[0-9;]*m//g')
  [[ "$(usage_line "$plain")" == *"Fable 9% (resets "* ]]
}
