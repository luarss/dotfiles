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

shopt -s extglob

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

USAGE_ENDPOINT="https://api.anthropic.com/api/oauth/usage"
USAGE_CACHE_TTL=300
USAGE_MAX_BACKOFF=1800
USAGE_CACHE_FILE="${CLAUDE_USAGE_CACHE:-${TMPDIR:-/tmp}/claude-statusline-usage.json}"
USAGE_FAILURES_FILE="${USAGE_CACHE_FILE}.failures"

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

NOW=""
ensure_now() {
    [[ -n "$NOW" ]] && return 0
    NOW=${EPOCHSECONDS:-$(date +%s)}
}

SCRIPT_DIR="${0%/*}"
[[ "$SCRIPT_DIR" == "$0" ]] && SCRIPT_DIR="."
MODELS_JSON="${SCRIPT_DIR}/models.json"

MODEL="unknown"
MODEL_ID=""
CWD="."
TRANSCRIPT=""
RL_5H=""
RL_7D=""
RL_5H_RESET=""
RL_7D_RESET=""
CTX_LIMIT_FROM_JSON=""

# Parse stdin JSON and models.json lookup in a single jq invocation.
_jq_filter='
  "MODEL=" + ((.model.display_name // "unknown") | tostring | @sh),
  "MODEL_ID=" + ((.model.id // "") | tostring | @sh),
  "CWD=" + ((.workspace.current_dir // ".") | tostring | @sh),
  "TRANSCRIPT=" + ((.transcript_path // "") | tostring | @sh),
  "RL_5H=" + ((.rate_limits.five_hour.used_percentage // "") | tostring | @sh),
  "RL_7D=" + ((.rate_limits.seven_day.used_percentage // "") | tostring | @sh),
  "RL_5H_RESET=" + ((.rate_limits.five_hour.resets_at // "") | tostring | @sh),
  "RL_7D_RESET=" + ((.rate_limits.seven_day.resets_at // "") | tostring | @sh),
  "CTX_LIMIT_FROM_JSON=" + (($models[0][.model.id // ""].contextWindow // "") | tostring | @sh)
'
if [[ -f "$MODELS_JSON" ]]; then
    _parsed=$(jq -r --slurpfile models "$MODELS_JSON" "$_jq_filter" 2>/dev/null)
else
    _parsed=$(jq -r --argjson models '[{}]' "$_jq_filter" 2>/dev/null)
fi
[[ -n "$_parsed" ]] && eval "$_parsed"

# Detect 1M-context models. Two paths:
#   1. models.json lookup (authoritative for third-party models whose API names
#      can't carry a "[1m]" tag — DeepSeek v4, Xiaomi MiMo v2.5). Update
#      models.json when adding a new provider, not this script.
#   2. Regex fallback for Anthropic models: explicit "[1m]" opt-in suffix, or
#      native-1M families (Fable 5, Mythos 5, Opus 5, Opus 4.6/4.7/4.8,
#      Sonnet 5, Sonnet 4.6). Haiku 4.5 is 200k and deliberately excluded.
if [[ -n "$CTX_LIMIT_FROM_JSON" ]]; then
    CTX_LIMIT=$CTX_LIMIT_FROM_JSON
else
    shopt -s nocasematch
    if [[ "$MODEL_ID" =~ 1m|fable|mythos|opus-5|sonnet-5|opus-4-[678]|sonnet-4-6 ]]; then
        CTX_LIMIT=$CTX_LIMIT_1M
    else
        CTX_LIMIT=$DEFAULT_CTX_LIMIT
    fi
    shopt -u nocasematch
fi

_cwd="$CWD"
while [[ "$_cwd" == */ && "$_cwd" != "/" ]]; do _cwd="${_cwd%/}"; done
DIR="${_cwd##*/}"
[[ -z "$DIR" ]] && DIR="/"

# ─────────────────────────────────────────────────────────────────────────────
# Git Status
# ─────────────────────────────────────────────────────────────────────────────

get_git_info() {
    GIT_INFO=""
    # Fast path: when GIT_DIR is unset and CWD is absolute, skip spawning git
    # if no ancestor contains a .git file or directory.
    if [[ -z "${GIT_DIR:-}" && "$CWD" == /* ]]; then
        local _dir="$CWD"
        while [[ ! -e "$_dir/.git" ]]; do
            [[ "$_dir" == "/" ]] && return 0
            _dir="${_dir%/*}"
            [[ -z "$_dir" ]] && _dir="/"
        done
    fi

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

    printf -v GIT_INFO " ${C_BLUE}git:(${C_RED}%s${C_BLUE})%s${C_RESET}" "$branch" "$dirty"
}

# ─────────────────────────────────────────────────────────────────────────────
# Token & Usage Metrics
# ─────────────────────────────────────────────────────────────────────────────

get_token_metrics() {
    [[ ! -f "$TRANSCRIPT" ]] && echo "0 0 0" && return 0

    awk '
    {
        if (index($0, "\"input_tokens\":")) {
            s = $0
            while (match(s, /"input_tokens":[0-9]+/)) {
                in_tok = substr(s, RSTART + 15, RLENGTH - 15) + 0
                s = substr(s, RSTART + RLENGTH)
            }
        }
        if (index($0, "\"cache_read_input_tokens\":")) {
            s = $0
            while (match(s, /"cache_read_input_tokens":[0-9]+/)) {
                cache_read = substr(s, RSTART + 26, RLENGTH - 26) + 0
                s = substr(s, RSTART + RLENGTH)
            }
        }
        if (index($0, "\"cache_creation_input_tokens\":")) {
            s = $0
            while (match(s, /"cache_creation_input_tokens":[0-9]+/)) {
                cache_create = substr(s, RSTART + 30, RLENGTH - 30) + 0
                s = substr(s, RSTART + RLENGTH)
            }
        }
        if (index($0, "\"output_tokens\":")) {
            s = $0
            while (match(s, /"output_tokens":[0-9]+/)) {
                out_tok += substr(s, RSTART + 16, RLENGTH - 16) + 0
                s = substr(s, RSTART + RLENGTH)
            }
        }
    }
    END {
        printf "%d %d %d\n", in_tok + cache_read + cache_create, out_tok + 0, cache_read + 0
    }
    ' "$TRANSCRIPT" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# Session Duration
# ─────────────────────────────────────────────────────────────────────────────

get_session_duration() {
    DURATION="0m"
    [[ ! -f "$TRANSCRIPT" ]] && return 0

    local start_time elapsed hours mins

    if [[ "$OSTYPE" == darwin* ]]; then
        start_time=$(stat -f %B "$TRANSCRIPT" 2>/dev/null || echo 0)
    else
        start_time=$(stat -c %W "$TRANSCRIPT" 2>/dev/null || echo 0)
        [[ "$start_time" == "0" ]] && start_time=$(stat -c %Y "$TRANSCRIPT" 2>/dev/null || echo 0)
    fi

    [[ -z "$start_time" || "$start_time" -le 0 ]] 2>/dev/null && return 0

    ensure_now
    elapsed=$((NOW - start_time))
    hours=$((elapsed / 3600))
    mins=$(((elapsed % 3600) / 60))

    if [[ $hours -gt 0 ]]; then
        DURATION="${hours}h${mins}m"
    else
        DURATION="${mins}m"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Context Progress Bar
# ─────────────────────────────────────────────────────────────────────────────

build_progress_bar() {
    local pct=$1
    local pct_int pct_dec pct_x10 filled empty bar="" color

    pct_int=${pct%.*}
    pct_int=${pct_int:-0}
    if [[ "$pct" == *.* ]]; then
        pct_dec=${pct#*.}
        pct_dec=${pct_dec:0:1}
    else
        pct_dec=0
    fi

    pct_x10=$(( 10#$pct_int * 10 + 10#$pct_dec ))
    filled=$(( (pct_x10 * BAR_WIDTH + 500) / 1000 ))
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

    PROGRESS_BAR="${color}[${bar} ${pct}%]${C_RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Subscription Usage (Pro/Max OAuth only)
# ─────────────────────────────────────────────────────────────────────────────

# Color a usage percentage by threshold, setting _REPLY to a colored "NN%".
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

    _REPLY="${color}${pct_int}%${C_RESET}"
}

# Format seconds-until-reset as a compact "(resets 2h13m)" / "(resets 14m)"
# string in _REPLY. Empty when the reset timestamp is absent or already in the past.
format_reset() {
    _REPLY=""
    local reset_at=$1 remaining days hours mins
    [[ -z "$reset_at" ]] && return 0

    ensure_now
    remaining=$((reset_at - NOW))
    [[ "$remaining" -le 0 ]] 2>/dev/null && return 0

    days=$((remaining / 86400))
    hours=$(((remaining % 86400) / 3600))
    mins=$(((remaining % 3600) / 60))

    if [[ $days -gt 0 ]]; then
        _REPLY=" ${C_DIM}(resets ${days}d${hours}h)${C_RESET}"
    elif [[ $hours -gt 0 ]]; then
        _REPLY=" ${C_DIM}(resets ${hours}h${mins}m)${C_RESET}"
    else
        _REPLY=" ${C_DIM}(resets ${mins}m)${C_RESET}"
    fi
}

# Project end-of-window 7d usage by linear extrapolation of the current burn
# rate. Given current usage% and the window reset time, we know how far through
# the 7-day window we are and scale the usage to the full window:
#   window_start   = reset_at - SEVEN_DAY_WINDOW
#   elapsed_frac   = (now - window_start) / SEVEN_DAY_WINDOW
#   projected_pct  = used_pct / elapsed_frac
# Sets _REPLY to a colored " →NN%" string (red if projected to exhaust the window,
# yellow past the warn threshold). No-op when we can't compute a stable value:
# no reset timestamp, no usage, or too early in the window.
project_7d_usage() {
    _REPLY=""
    local used_pct=$1 reset_at=$2 window_start elapsed p_int p_frac p_scale p_scaled denom pct_int color
    [[ -z "$used_pct" || -z "$reset_at" ]] && return 0

    ensure_now
    window_start=$((reset_at - SEVEN_DAY_WINDOW))
    elapsed=$((NOW - window_start))
    [[ "$elapsed" -le 0 ]] 2>/dev/null && return 0

    # Too early in the window for a meaningful projection (< PROJECT_MIN_ELAPSED_FRAC = 0.02).
    (( elapsed * 100 < 2 * SEVEN_DAY_WINDOW )) && return 0

    p_int=${used_pct%.*}
    if [[ "$used_pct" == *.* ]]; then
        p_frac=${used_pct#*.}
        p_frac=${p_frac:0:3}
        while [[ ${#p_frac} -lt 3 ]]; do p_frac+="0"; done
        p_scale=1000
        p_scaled=$(( 10#${p_int:-0} * 1000 + 10#$p_frac ))
    else
        p_scale=1
        p_scaled=$(( 10#${p_int:-0} ))
    fi

    denom=$(( elapsed * p_scale ))
    pct_int=$(( (p_scaled * SEVEN_DAY_WINDOW + denom / 2) / denom ))

    if [[ $pct_int -ge 100 ]]; then
        color=$C_RED
    elif [[ $pct_int -ge $USAGE_WARN_PCT ]]; then
        color=$C_YELLOW
    else
        color=$C_GREEN
    fi

    _REPLY=" ${C_DIM}→${C_RESET}${color}${pct_int}%${C_RESET}"
}

read_oauth_token() {
    if [[ "$OSTYPE" == darwin* ]]; then
        local config_dir_hash
        config_dir_hash=$(printf %s "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" | shasum -a 256 | cut -c1-8)
        security find-generic-password -s "Claude Code-credentials-$config_dir_hash" -w 2>/dev/null ||
            security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null
    else
        cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" 2>/dev/null
    fi | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
}

fetch_usage() {
    if [[ -n "${CLAUDE_USAGE_FETCH_CMD:-}" ]]; then
        bash -c "$CLAUDE_USAGE_FETCH_CMD"
        return
    fi

    local token
    token=$(read_oauth_token)
    [[ -z "$token" ]] && return 1

    curl -sS --max-time 3 "$USAGE_ENDPOINT" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H @- <<< "Authorization: Bearer $token"
}

refresh_usage_cache() {
    local temp_file
    temp_file=$(mktemp "${USAGE_CACHE_FILE}.XXXXXX") || return 0

    if fetch_usage > "$temp_file" 2>/dev/null &&
       jq -e '.limits | type == "array"' "$temp_file" >/dev/null 2>&1; then
        mv "$temp_file" "$USAGE_CACHE_FILE"
        rm -f "$USAGE_FAILURES_FILE"
        return 0
    fi

    rm -f "$temp_file"
    echo $(( $(read_failure_count) + 1 )) > "$USAGE_FAILURES_FILE"
    [[ -f "$USAGE_CACHE_FILE" ]] || echo '{}' > "$USAGE_CACHE_FILE"
}

read_failure_count() {
    local count=""
    [[ -f "$USAGE_FAILURES_FILE" ]] && read -r count < "$USAGE_FAILURES_FILE"
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    echo "$count"
}

usage_refresh_interval() {
    local failures interval
    failures=$(read_failure_count)
    interval=$USAGE_CACHE_TTL
    while (( failures > 0 && interval < USAGE_MAX_BACKOFF )); do
        interval=$(( interval * 2 ))
        failures=$(( failures - 1 ))
    done
    (( interval > USAGE_MAX_BACKOFF )) && interval=$USAGE_MAX_BACKOFF
    echo "$interval"
}

file_age_seconds() {
    local modified_at
    if [[ "$OSTYPE" == darwin* ]]; then
        modified_at=$(stat -f %m "$1" 2>/dev/null || echo 0)
    else
        modified_at=$(stat -c %Y "$1" 2>/dev/null || echo 0)
    fi
    ensure_now
    FILE_AGE=$(( NOW - modified_at ))
}

ensure_usage_cache() {
    if [[ ! -f "$USAGE_CACHE_FILE" ]]; then
        refresh_usage_cache
        return 0
    fi

    file_age_seconds "$USAGE_CACHE_FILE"
    if [[ $FILE_AGE -ge $(usage_refresh_interval) ]]; then
        touch "$USAGE_CACHE_FILE"
        ( refresh_usage_cache </dev/null >/dev/null 2>&1 & )
    fi
}

read_model_scoped_limits() {
    [[ -f "$USAGE_CACHE_FILE" ]] || return 0
    local raw
    raw=$(<"$USAGE_CACHE_FILE")
    [[ -z "$raw" || "$raw" == "{}" ]] && return 0
    ensure_now
    jq -r --argjson now "$NOW" '
        .limits[]?
        | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
        | ((.resets_at // "") | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | (try fromdateiso8601 catch "")) as $reset_at
        | select(($reset_at | type) != "number" or $reset_at > $now)
        | [.scope.model.display_name, (.percent // 0), $reset_at]
        | @tsv
    ' <<< "$raw" 2>/dev/null
}

load_model_scoped_limits() {
    MODEL_SCOPED_LIMITS=""
    [[ "${SHOW_USAGE_LIMITS:-0}" != "1" ]] && return 0
    [[ -z "$RL_5H" && -z "$RL_7D" ]] && return 0
    ensure_usage_cache
    MODEL_SCOPED_LIMITS=$(read_model_scoped_limits)
}

# Subscription-usage line. No-op unless SHOW_USAGE_LIMITS=1 (default profile
# only) and at least one window is present. Sets USAGE_SEGMENT.
#   mode "full"    — "⏳ 5h 36% (resets 2h13m) · 7d 18% (resets 2d21h) →45% · Fable 9% (resets 2d21h)"
#   mode "compact" — "⏳ 5h 36% 7d 18% →45% Fable 9%"
build_usage_segment() {
    USAGE_SEGMENT=""
    [[ "${SHOW_USAGE_LIMITS:-0}" != "1" ]] && return 0
    local mode=${1:-full} separator=" " part parts=() line="" name pct reset_at

    if [[ "$mode" == "full" ]]; then
        separator=" ${C_DIM}·${C_RESET} "
        if [[ -n "$RL_5H" ]]; then
            colorize_usage_pct "$RL_5H"; part="${C_DIM}5h${C_RESET} ${_REPLY}"
            format_reset "$RL_5H_RESET"; part+="$_REPLY"
            parts+=("$part")
        fi
        if [[ -n "$RL_7D" ]]; then
            colorize_usage_pct "$RL_7D"; part="${C_DIM}7d${C_RESET} ${_REPLY}"
            format_reset "$RL_7D_RESET"; part+="$_REPLY"
            project_7d_usage "$RL_7D" "$RL_7D_RESET"; part+="$_REPLY"
            parts+=("$part")
        fi
    else
        if [[ -n "$RL_5H" ]]; then
            colorize_usage_pct "$RL_5H"
            parts+=("${C_DIM}5h${C_RESET} ${_REPLY}")
        fi
        if [[ -n "$RL_7D" ]]; then
            colorize_usage_pct "$RL_7D"; part="${C_DIM}7d${C_RESET} ${_REPLY}"
            project_7d_usage "$RL_7D" "$RL_7D_RESET"; part+="$_REPLY"
            parts+=("$part")
        fi
    fi

    if [[ -n "$MODEL_SCOPED_LIMITS" ]]; then
        while IFS=$'\t' read -r name pct reset_at; do
            [[ -z "$name" ]] && continue
            colorize_usage_pct "$pct"; part="${C_DIM}${name}${C_RESET} ${_REPLY}"
            if [[ "$mode" == "full" ]]; then
                format_reset "$reset_at"; part+="$_REPLY"
            fi
            parts+=("$part")
        done <<< "$MODEL_SCOPED_LIMITS"
    fi

    [[ ${#parts[@]} -eq 0 ]] && return 0

    for part in "${parts[@]}"; do
        [[ -n "$line" ]] && line+="$separator"
        line+="$part"
    done
    USAGE_SEGMENT="${C_DIM}⏳${C_RESET} ${line}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    local total_in=0 out_tok=0 cache_read=0 ctx_tenths ctx_pct cache_pct=0
    local cache_color cache_warn=""

    DURATION="0m"
    if [[ -f "$TRANSCRIPT" ]]; then
        read -r total_in out_tok cache_read <<< "$(get_token_metrics)"
        total_in=${total_in:-0}
        out_tok=${out_tok:-0}
        cache_read=${cache_read:-0}
        get_session_duration
    fi

    ctx_tenths=$(( (total_in * 1000 + CTX_LIMIT / 2) / CTX_LIMIT ))
    ctx_pct="$((ctx_tenths / 10)).$((ctx_tenths % 10))"
    if [[ $total_in -gt 0 ]]; then
        cache_pct=$(( (cache_read * 100 + total_in / 2) / total_in ))
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

    get_git_info
    build_progress_bar "$ctx_pct"

    # Render the main line with a given cache-warning string into MAIN_LINE.
    render() {
        printf -v MAIN_LINE "%s➜%s  %s%s%s%s %s[%s]%s %s[↑%dk/↓%dk %s⚡%s%%%s%s]%s%s %s %s⏱ %s%s" \
            "$C_BOLD_GREEN" "$C_RESET" \
            "$C_CYAN" "$DIR" "$C_RESET" \
            "$GIT_INFO" \
            "$C_DIM" "$MODEL" "$C_RESET" \
            "$C_DIM" "$((total_in / 1000))" "$((out_tok / 1000))" \
            "$cache_color" "$cache_pct" "$C_RESET" "$C_DIM" "$C_RESET" \
            "$1" \
            "$PROGRESS_BAR" \
            "$C_CYAN" "$DURATION" "$C_RESET"
    }

    # Width-aware degradation. Claude Code exports COLUMNS (v2.1.153+); fall back
    # to 80. Each line emits the first candidate that fits the terminal:
    #   main line  — with cache-warning text, then without (red ⚡% still signals it)
    #   usage line — full (with resets), then compact, then omitted
    local cols=${COLUMNS:-80} usage_line=""
    load_model_scoped_limits

    if [[ -n "$cache_warn" ]]; then
        render "$cache_warn"
        visible_len "$MAIN_LINE"
        if [[ $VISIBLE_LEN -gt $cols ]]; then
            render ""
        fi
    else
        render ""
    fi

    if [[ "${SHOW_USAGE_LIMITS:-0}" == "1" && ( -n "$RL_5H" || -n "$RL_7D" || -n "$MODEL_SCOPED_LIMITS" ) ]]; then
        build_usage_segment full
        if [[ -n "$USAGE_SEGMENT" ]]; then
            visible_len "$USAGE_SEGMENT"
            if [[ $VISIBLE_LEN -le $cols ]]; then
                usage_line=$USAGE_SEGMENT
            else
                build_usage_segment compact
                if [[ -n "$USAGE_SEGMENT" ]]; then
                    visible_len "$USAGE_SEGMENT"
                    [[ $VISIBLE_LEN -le $cols ]] && usage_line=$USAGE_SEGMENT
                fi
            fi
        fi
    fi

    printf '%s' "$MAIN_LINE"
    [[ -n "$usage_line" ]] && printf '\n%s' "$usage_line"
    return 0
}

# Visible (display-cell) length of a string: strip ANSI escape sequences, count
# characters, then add 1 per double-width glyph (the emoji-ish symbols render as
# 2 cells in most terminals but count as 1 code point). Used to fit output to the
# terminal width. Sets VISIBLE_LEN.
visible_len() {
    local stripped no_wide wide
    stripped="${1//$'\033'\[*([0-9;])m/}"
    # Count occurrences of known 2-cell glyphs: ➜ ⏱ ⏳ ⚡ ⚠
    no_wide="${stripped//➜/}"
    no_wide="${no_wide//⏱/}"
    no_wide="${no_wide//⏳/}"
    no_wide="${no_wide//⚡/}"
    no_wide="${no_wide//⚠/}"
    wide=$(( ${#stripped} - ${#no_wide} ))
    VISIBLE_LEN=$(( ${#stripped} + wide ))
}

main
