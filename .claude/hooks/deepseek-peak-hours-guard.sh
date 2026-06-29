#!/usr/bin/env bash
# Block s-claude during DeepSeek's peak-hour surcharge windows (UTC): 01:00-04:00 and 14:00-18:00.
# Checks ANTHROPIC_BASE_URL env var first; falls back to reading from the active profile's
# settings.json since env vars from settings.json are not exported to hook subprocesses.
base_url="${ANTHROPIC_BASE_URL:-}"
if [[ -z "$base_url" ]]; then
    config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    base_url=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$config_dir/settings.json" 2>/dev/null)
fi
[[ "$base_url" == *"deepseek"* ]] || exit 0

hour=$((10#$(date -u +%H)))

if (( hour >= 1 && hour < 4 )) || (( hour >= 14 && hour < 18 )); then
    now=$(date -u +%H:%M)
    printf 'DeepSeek peak-hour surcharge in effect (01:00–04:00 UTC and 14:00–18:00 UTC). Current UTC: %s. Use another profile or try later.\n' "$now" >&2
    exit 2
fi
