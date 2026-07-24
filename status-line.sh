#!/bin/bash
#
# Claude Code Status Line
# A clean, informative status bar for Claude Code CLI
# Referenced from https://github.com/feiskyer/claude-code-settings on May 7 2026
#
# ─────────────────────────────────────────────────────────────────────────────
# Dependencies
# ─────────────────────────────────────────────────────────────────────────────
#
#   Required:
#     jq        JSON parser for reading Claude's input
#               Install: brew install jq (macOS) | apt install jq (Linux)
#
#   Optional:
#     git       For branch/dirty status (skip if not in a repo)
#
#   Built-in (no install needed):
#     awk, grep, stat, date, basename
#
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

BAR_WIDTH=10
CONTEXT_WARN_PCT=70
CONTEXT_CRIT_PCT=90

# Subscription usage thresholds (5-hour / 7-day rate-limit windows). These come
# straight from Claude Code's stdin JSON (.rate_limits.*.used_percentage) and
# are present ONLY for Claude.ai Pro/Max OAuth sessions — third-party providers
# never send them. Gated behind SHOW_USAGE_LIMITS so only the default profile
# shows them (set via providers.json overrides.env).
USAGE_WARN_PCT=70
USAGE_CRIT_PCT=90
DEFAULT_CTX_LIMIT=200000
CTX_LIMIT_1M=1000000

# Length of the 7-day rate-limit window, in seconds (7 * 24 * 3600). Used to
# derive the window's start (resets_at - SEVEN_DAY_WINDOW) so we can project
# end-of-window usage from the current rate of consumption.
SEVEN_DAY_WINDOW=604800
# Skip the projection until at least this fraction of the window has elapsed —
# early in the window the elapsed time is tiny and the linear extrapolation is
# wildly unstable (a 1% burn in the first 10 minutes projects to ~1000%).
PROJECT_MIN_ELAPSED_FRAC=0.02

# Cache hit rate thresholds.
# ~90% is the healthy target on active sessions; the Claude Code team alerts
# on cache breaks. Dropping ~20 points typically signals cache busting (e.g.
# resumed session, timestamp in system prompt), which can turn a $0.50/hr
# session into $5–10/hr.
# Refs:
#   https://claude.com/blog/lessons-from-building-claude-code-prompt-caching-is-everything
#   https://www.claudecodecamp.com/p/how-prompt-caching-actually-works-in-claude-code
#   https://github.com/cnighswonger/claude-code-cache-fix
CACHE_WARN_PCT=90
CACHE_CRIT_PCT=70
CACHE_MIN_TOKENS=10000

# Colors (using $'...' for proper escape sequence interpretation)
C_RESET=$'\033[0m'
C_BOLD_GREEN=$'\033[1;32m'
C_CYAN=$'\033[0;36m'
C_BLUE=$'\033[1;34m'
C_RED=$'\033[0;31m'
C_YELLOW=$'\033[0;33m'
C_GREEN=$'\033[0;32m'
C_MAGENTA=$'\033[0;35m'
C_DIM=$'\033[2m'

# ─────────────────────────────────────────────────────────────────────────────
# Input Parsing
# ─────────────────────────────────────────────────────────────────────────────

INPUT=$(cat)

MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "unknown"')
MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // ""')
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // "."')

# Detect 1M-context models. Two paths:
#   1. models.json lookup (authoritative for third-party models whose API names
#      can't carry a "[1m]" tag — DeepSeek v4, Xiaomi MiMo v2.5). Update
#      models.json when adding a new provider, not this script.
#   2. Regex fallback for Anthropic models: explicit "[1m]" opt-in suffix, or
#      native-1M families (Fable 5, Mythos 5, Opus 4.6/4.7/4.8).
MODELS_JSON="$(dirname "$0")/models.json"
CTX_LIMIT_FROM_JSON=""
if [[ -f "$MODELS_JSON" ]]; then
    CTX_LIMIT_FROM_JSON=$(jq -r --arg id "$MODEL_ID" '.[$id].contextWindow // empty' "$MODELS_JSON" 2>/dev/null)
fi

if [[ -n "$CTX_LIMIT_FROM_JSON" ]]; then
    CTX_LIMIT=$CTX_LIMIT_FROM_JSON
elif echo "$MODEL_ID" | grep -qiE '1m|fable|mythos|opus-4-[678]'; then
    CTX_LIMIT=$CTX_LIMIT_1M
else
    CTX_LIMIT=$DEFAULT_CTX_LIMIT
fi
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
DIR=$(basename "$CWD")

# Subscription rate-limit usage. Each window may be independently absent (// empty),
# and the whole block is absent outside Pro/Max OAuth sessions.
RL_5H=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty')
RL_7D=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Window reset times (unix epoch seconds, // empty when absent). Used to show
# how long until each window resets.
RL_5H_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty')
RL_7D_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ─────────────────────────────────────────────────────────────────────────────
# Git Status
# ─────────────────────────────────────────────────────────────────────────────

get_git_info() {
    git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || return 0

    local branch dirty=""
    branch=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null)
    [[ -z "$branch" ]] && branch="detached"

    # Check for uncommitted changes
    if ! git -C "$CWD" --no-optional-locks diff --quiet 2>/dev/null ||
       ! git -C "$CWD" --no-optional-locks diff --cached --quiet 2>/dev/null ||
       [[ -n $(git -C "$CWD" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null) ]]; then
        dirty=" ${C_YELLOW}✗"
    fi

    printf " ${C_BLUE}git:(${C_RED}%s${C_BLUE})%s${C_RESET}" "$branch" "$dirty"
}

# ─────────────────────────────────────────────────────────────────────────────
# Token & Usage Metrics
# ─────────────────────────────────────────────────────────────────────────────

get_token_metrics() {
    [[ ! -f "$TRANSCRIPT" ]] && echo "0 0 0" && return 0

    local in_tok cache_read cache_create out_tok total_in

    in_tok=$(grep -oE '"input_tokens":[0-9]+' "$TRANSCRIPT" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    cache_read=$(grep -oE '"cache_read_input_tokens":[0-9]+' "$TRANSCRIPT" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    cache_create=$(grep -oE '"cache_creation_input_tokens":[0-9]+' "$TRANSCRIPT" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    out_tok=$(grep -oE '"output_tokens":[0-9]+' "$TRANSCRIPT" 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')

    in_tok=${in_tok:-0}
    cache_read=${cache_read:-0}
    cache_create=${cache_create:-0}
    out_tok=${out_tok:-0}

    total_in=$((in_tok + cache_read + cache_create))
    echo "$total_in $out_tok $cache_read"
}

# ─────────────────────────────────────────────────────────────────────────────
# Session Duration
# ─────────────────────────────────────────────────────────────────────────────

get_session_duration() {
    [[ ! -f "$TRANSCRIPT" ]] && echo "0m" && return 0

    local start_time now elapsed hours mins

    if [[ "$OSTYPE" == darwin* ]]; then
        start_time=$(stat -f %B "$TRANSCRIPT" 2>/dev/null || echo 0)
    else
        start_time=$(stat -c %W "$TRANSCRIPT" 2>/dev/null || echo 0)
        [[ "$start_time" == "0" ]] && start_time=$(stat -c %Y "$TRANSCRIPT" 2>/dev/null || echo 0)
    fi

    [[ -z "$start_time" || "$start_time" -le 0 ]] 2>/dev/null && echo "0m" && return 0

    now=$(date +%s)
    elapsed=$((now - start_time))
    hours=$((elapsed / 3600))
    mins=$(((elapsed % 3600) / 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours}h${mins}m"
    else
        echo "${mins}m"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Context Progress Bar
# ─────────────────────────────────────────────────────────────────────────────

build_progress_bar() {
    local pct=$1
    local pct_int filled empty bar="" color

    pct_int=${pct%.*}
    pct_int=${pct_int:-0}

    filled=$(awk "BEGIN {printf \"%.0f\", ($pct / 100) * $BAR_WIDTH}")
    filled=${filled:-0}
    empty=$((BAR_WIDTH - filled))

    # Color based on usage level
    if [[ $pct_int -ge $CONTEXT_CRIT_PCT ]]; then
        color=$C_RED
    elif [[ $pct_int -ge $CONTEXT_WARN_PCT ]]; then
        color=$C_YELLOW
    else
        color=$C_GREEN
    fi

    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    printf "%b[%s %s%%]%b" "$color" "$bar" "$pct" "$C_RESET"
}

# ─────────────────────────────────────────────────────────────────────────────
# Subscription Usage (Pro/Max OAuth only)
# ─────────────────────────────────────────────────────────────────────────────

# Color a usage percentage by threshold, returning a colored "NN%".
colorize_usage_pct() {
    local pct=$1 pct_int color
    pct_int=${pct%.*}
    pct_int=${pct_int:-0}

    if [[ $pct_int -ge $USAGE_CRIT_PCT ]]; then
        color=$C_RED
    elif [[ $pct_int -ge $USAGE_WARN_PCT ]]; then
        color=$C_YELLOW
    else
        color=$C_GREEN
    fi

    printf "%b%s%%%b" "$color" "$pct_int" "$C_RESET"
}

# Format seconds-until-reset as a compact "(resets 2h13m)" / "(resets 14m)"
# string. Empty when the reset timestamp is absent or already in the past.
format_reset() {
    local reset_at=$1 now remaining days hours mins
    [[ -z "$reset_at" ]] && return 0

    now=$(date +%s)
    remaining=$((reset_at - now))
    [[ "$remaining" -le 0 ]] 2>/dev/null && return 0

    days=$((remaining / 86400))
    hours=$(((remaining % 86400) / 3600))
    mins=$(((remaining % 3600) / 60))

    if [[ $days -gt 0 ]]; then
        printf " %b(resets %dd%dh)%b" "$C_DIM" "$days" "$hours" "$C_RESET"
    elif [[ $hours -gt 0 ]]; then
        printf " %b(resets %dh%dm)%b" "$C_DIM" "$hours" "$mins" "$C_RESET"
    else
        printf " %b(resets %dm)%b" "$C_DIM" "$mins" "$C_RESET"
    fi
}

# Project end-of-window 7d usage by linear extrapolation of the current burn
# rate. Given current usage% and the window reset time, we know how far through
# the 7-day window we are and scale the usage to the full window:
#   window_start   = reset_at - SEVEN_DAY_WINDOW
#   elapsed_frac   = (now - window_start) / SEVEN_DAY_WINDOW
#   projected_pct  = used_pct / elapsed_frac
# Emits a colored " → proj NN%" string (red if projected to exhaust the window,
# yellow past the warn threshold). No-op when we can't compute a stable value:
# no reset timestamp, no usage, or too early in the window.
project_7d_usage() {
    local used_pct=$1 reset_at=$2 now window_start elapsed elapsed_frac projected pct_int color
    [[ -z "$used_pct" || -z "$reset_at" ]] && return 0

    now=$(date +%s)
    window_start=$((reset_at - SEVEN_DAY_WINDOW))
    elapsed=$((now - window_start))
    [[ "$elapsed" -le 0 ]] 2>/dev/null && return 0

    elapsed_frac=$(awk "BEGIN {printf \"%.6f\", $elapsed / $SEVEN_DAY_WINDOW}")
    # Too early in the window for a meaningful projection.
    awk "BEGIN {exit !($elapsed_frac < $PROJECT_MIN_ELAPSED_FRAC)}" && return 0

    projected=$(awk "BEGIN {printf \"%.0f\", $used_pct / $elapsed_frac}")
    pct_int=${projected:-0}

    if [[ $pct_int -ge 100 ]]; then
        color=$C_RED
    elif [[ $pct_int -ge $USAGE_WARN_PCT ]]; then
        color=$C_YELLOW
    else
        color=$C_GREEN
    fi

    printf " %b→ proj%b %b%s%%%b" "$C_DIM" "$C_RESET" "$color" "$pct_int" "$C_RESET"
}

# 5h/7d subscription-usage readout. No-op unless SHOW_USAGE_LIMITS=1 (default
# profile only) and at least one rate-limit window is present.
#   mode "full"    — "⏳ usage: 5h limit 36% (resets 2h13m) · 7d limit 18% (resets 2d21h) → proj 45%"
#   mode "compact" — "⏳ 5h 36% 7d 18% →45%"   (labels + resets dropped to save space)
# The "→ proj NN%" tail is the 7-day usage projected to the end of the window at
# the current burn rate (see project_7d_usage).
build_usage_segment() {
    [[ "${SHOW_USAGE_LIMITS:-0}" != "1" ]] && return 0
    local mode=${1:-full} seg=""

    if [[ "$mode" == "compact" ]]; then
        [[ -n "$RL_5H" ]] && seg+=" ${C_DIM}5h${C_RESET} $(colorize_usage_pct "$RL_5H")"
        [[ -n "$RL_7D" ]] && seg+=" ${C_DIM}7d${C_RESET} $(colorize_usage_pct "$RL_7D")$(project_7d_usage "$RL_7D" "$RL_7D_RESET")"
        [[ -z "$seg" ]] && return 0
        printf " %b⏳%b%s" "$C_DIM" "$C_RESET" "$seg"
        return 0
    fi

    [[ -n "$RL_5H" ]] && seg+=" ${C_DIM}5h limit${C_RESET} $(colorize_usage_pct "$RL_5H")$(format_reset "$RL_5H_RESET")"
    [[ -n "$RL_7D" ]] && seg+=" ${C_DIM}·${C_RESET} ${C_DIM}7d limit${C_RESET} $(colorize_usage_pct "$RL_7D")$(format_reset "$RL_7D_RESET")$(project_7d_usage "$RL_7D" "$RL_7D_RESET")"
    [[ -z "$seg" ]] && return 0

    printf " %b⏳ usage:%b%s" "$C_DIM" "$C_RESET" "$seg"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    local total_in out_tok cache_read ctx_pct cache_pct duration git_info usage_seg
    local cache_color cache_warn=""

    read -r total_in out_tok cache_read <<< "$(get_token_metrics)"
    total_in=${total_in:-0}
    out_tok=${out_tok:-0}
    cache_read=${cache_read:-0}

    ctx_pct=$(awk "BEGIN {printf \"%.1f\", ($total_in / $CTX_LIMIT) * 100}")
    if [[ $total_in -gt 0 ]]; then
        cache_pct=$(awk "BEGIN {printf \"%.0f\", ($cache_read / $total_in) * 100}")
    else
        cache_pct=0
    fi

    # Tiered cache-hit warning. Stays quiet until the session has enough
    # tokens for the ratio to be informative.
    cache_color=$C_DIM
    if [[ $total_in -ge $CACHE_MIN_TOKENS ]]; then
        if [[ $cache_pct -lt $CACHE_CRIT_PCT ]]; then
            cache_color=$C_RED
            cache_warn=" ${C_RED}⚠ EXPENSIVE: low cache hit${C_RESET}"
        elif [[ $cache_pct -lt $CACHE_WARN_PCT ]]; then
            cache_color=$C_YELLOW
        fi
    fi

    duration=$(get_session_duration)
    git_info=$(get_git_info)

    # Render the line with a given cache-warning string and usage segment. The
    # degradation chain below swaps these two args to shrink the line.
    render() {
        printf "%b➜%b  %b%s%b%s %b[%s]%b %b[↑%dk/↓%dk %b⚡%s%%%b%b]%b%s %s %b⏱ %s%b%s" \
            "$C_BOLD_GREEN" "$C_RESET" \
            "$C_CYAN" "$DIR" "$C_RESET" \
            "$git_info" \
            "$C_DIM" "$MODEL" "$C_RESET" \
            "$C_DIM" "$((total_in / 1000))" "$((out_tok / 1000))" \
            "$cache_color" "$cache_pct" "$C_RESET" "$C_DIM" "$C_RESET" \
            "$1" \
            "$(build_progress_bar "$ctx_pct")" \
            "$C_CYAN" "$duration" "$C_RESET" \
            "$2"
    }

    # Width-aware degradation. Claude Code exports COLUMNS (v2.1.153+); fall back
    # to 80. We try progressively smaller renderings and emit the first that fits
    # the terminal, so a narrow window drops the least useful detail first instead
    # of getting truncated mid-segment. Order, most→least verbose:
    #   1. full usage + reset times + cache warning
    #   2. compact usage (no labels/resets) + cache warning
    #   3. compact usage, no cache-warning text (red ⚡% still signals it)
    #   4. no usage, no cache-warning text
    local cols=${COLUMNS:-80} line
    local usage_full usage_compact
    usage_full=$(build_usage_segment full)
    usage_compact=$(build_usage_segment compact)

    for line in \
        "$(render "$cache_warn" "$usage_full")" \
        "$(render "$cache_warn" "$usage_compact")" \
        "$(render "$cache_warn" "")" \
        "$(render "" "")"; do
        if [[ $(visible_len "$line") -le $cols ]]; then
            printf '%s' "$line"
            return 0
        fi
    done

    # Even the smallest form overflows — emit it anyway (terminal will truncate).
    printf '%s' "$line"
}

# Visible (display-cell) length of a string: strip ANSI escape sequences, count
# characters, then add 1 per double-width glyph (the emoji-ish symbols render as
# 2 cells in most terminals but count as 1 code point). Used to fit output to the
# terminal width.
visible_len() {
    local stripped wide
    stripped=$(printf '%s' "$1" | sed -E $'s/\033\\[[0-9;]*m//g')
    # Count occurrences of known 2-cell glyphs: ➜ ⏱ ⏳ ⚡ ⚠
    wide=$(printf '%s' "$stripped" | grep -oE '➜|⏱|⏳|⚡|⚠' | grep -c .)
    printf '%s' "$(( ${#stripped} + wide ))"
}

main
