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

# Detect 1M-context models. Three cases:
#   1. Explicit "1m" suffix on an opt-in beta model (Anthropic, Vertex, Bedrock),
#      e.g. claude-sonnet-4-5[1m].
#   2. Models with a 1M window natively: Fable 5, Mythos 5, Opus 4.6/4.7/4.8.
#      (Sonnet 4.6, Haiku 4.5 and older Sonnet/Opus stay at 200K.)
#   3. Third-party 1M models whose API names can't carry a "[1m]" tag, so they
#      are hardcoded here: DeepSeek v4 (flash/pro) and Xiaomi MiMo v2.5 (incl. pro).
# Update the family list below when a new 1M-native model ships.
if echo "$MODEL_ID" | grep -qiE '1m|fable|mythos|opus-4-[678]|deepseek-v4|mimo-v2'; then
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

# 5h/7d subscription-usage readout. No-op unless SHOW_USAGE_LIMITS=1 (default
# profile only) and at least one rate-limit window is present.
#   mode "full"    — "⏳ usage: 5h limit 36% (resets 2h13m) · 7d limit 18% (resets 2d21h)"
#   mode "compact" — "⏳ 5h 36% 7d 18%"   (labels + resets dropped to save space)
build_usage_segment() {
    [[ "${SHOW_USAGE_LIMITS:-0}" != "1" ]] && return 0
    local mode=${1:-full} seg=""

    if [[ "$mode" == "compact" ]]; then
        [[ -n "$RL_5H" ]] && seg+=" ${C_DIM}5h${C_RESET} $(colorize_usage_pct "$RL_5H")"
        [[ -n "$RL_7D" ]] && seg+=" ${C_DIM}7d${C_RESET} $(colorize_usage_pct "$RL_7D")"
        [[ -z "$seg" ]] && return 0
        printf " %b⏳%b%s" "$C_DIM" "$C_RESET" "$seg"
        return 0
    fi

    [[ -n "$RL_5H" ]] && seg+=" ${C_DIM}5h limit${C_RESET} $(colorize_usage_pct "$RL_5H")$(format_reset "$RL_5H_RESET")"
    [[ -n "$RL_7D" ]] && seg+=" ${C_DIM}·${C_RESET} ${C_DIM}7d limit${C_RESET} $(colorize_usage_pct "$RL_7D")$(format_reset "$RL_7D_RESET")"
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
