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
}

teardown() {
  rm -rf "$WORKDIR"
}

# ─── helpers ──────────────────────────────────────────────────────────────────

# Run the status line at a given width. $1=COLUMNS $2=JSON $3=SHOW_USAGE_LIMITS(=1)
sl() {
  local cols="$1" json="$2" show="${3-1}"
  COLUMNS="$cols" SHOW_USAGE_LIMITS="$show" \
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
  [[ "$out" == *"5h limit"* ]]
  [[ "$out" != *"resets"* ]]
}

# ─── colour by threshold ──────────────────────────────────────────────────────

@test "usage percentage turns red past the critical threshold" {
  # 95% >= USAGE_CRIT_PCT (90) → red (\033[0;31m) precedes "95%"
  out=$(sl 300 "$(json_5h 95 "$(( $(now) + 8000 ))")")
  [[ "$out" == *$'\033[0;31m'"95%"* ]]
}

# ─── width-aware degradation ──────────────────────────────────────────────────

@test "full form at a wide terminal includes label and reset times" {
  out=$(sl 300 "$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")")
  [[ "$out" == *"usage:"* ]]
  [[ "$out" == *"5h limit"* ]]
  [[ "$out" == *"resets"* ]]
}

@test "falls back to compact form when full does not fit" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  full=$(sl 9999 "$json")
  full_len=$(vislen "$full")
  # One column too narrow for the full form.
  out=$(sl "$(( full_len - 1 ))" "$json")
  [[ "$out" == *"⏳"* ]]            # usage still present
  [[ "$out" == *"5h"* ]]
  [[ "$out" != *"limit"* ]]         # labels dropped
  [[ "$out" != *"resets"* ]]        # reset times dropped
  [ "$(vislen "$out")" -le "$(( full_len - 1 ))" ]   # and it actually fits
}

@test "drops usage entirely when even compact does not fit" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  # Measure the compact form's width, then go one narrower.
  full=$(sl 9999 "$json")
  full_len=$(vislen "$full")
  compact=$(sl "$(( full_len - 1 ))" "$json")
  compact_len=$(vislen "$compact")
  out=$(sl "$(( compact_len - 1 ))" "$json")
  [[ "$out" != *"⏳"* ]]
  [[ "$out" != *"5h"* ]]
  # Core segments survive.
  [[ "$out" == *"proj"* ]]
  [[ "$out" == *"Test"* ]]
}

@test "rendered line never exceeds COLUMNS across a range of widths" {
  json=$(json_both 36 "$(( $(now) + 8000 ))" 18 "$(( $(now) + 184200 ))")
  for cols in 200 130 100 80; do
    out=$(sl "$cols" "$json")
    len=$(vislen "$out")
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
