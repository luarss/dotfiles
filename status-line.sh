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

# Detect 1M context models: "1m" suffix (Anthropic, Vertex, Bedrock) or Fable (1M natively)
if echo "$MODEL_ID" | grep -qiE '1m|fable'; then
    CTX_LIMIT=$CTX_LIMIT_1M
else
    CTX_LIMIT=$DEFAULT_CTX_LIMIT
fi
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
DIR=$(basename "$CWD")

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
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    local total_in out_tok cache_read ctx_pct cache_pct duration git_info
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

    # Output
    printf "%b➜%b  %b%s%b%s %b[%s]%b %b[↑%dk/↓%dk %b⚡%s%%%b%b]%b%s %s %b⏱ %s%b" \
        "$C_BOLD_GREEN" "$C_RESET" \
        "$C_CYAN" "$DIR" "$C_RESET" \
        "$git_info" \
        "$C_DIM" "$MODEL" "$C_RESET" \
        "$C_DIM" "$((total_in / 1000))" "$((out_tok / 1000))" \
        "$cache_color" "$cache_pct" "$C_RESET" "$C_DIM" "$C_RESET" \
        "$cache_warn" \
        "$(build_progress_bar "$ctx_pct")" \
        "$C_CYAN" "$duration" "$C_RESET"
}

main
