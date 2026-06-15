#!/usr/bin/env bash
# DB Rate Limit — PreToolUse hook
# Sliding-window rate limiter for MySQL access: blocks once more than
# $LIMIT qualifying calls happen within the last $WINDOW seconds.
#
# Covers two call types (registered on matchers "Bash" and "mcp__.*mysql.*"
# in settings.base.json + the rtk override in providers.json):
#   - mysql / mariadb CLI invoked to run a statement via the Bash tool
#   - mcp__*mysql* MCP tool calls
#
# Exit codes: 0 = allow, 2 = block. Counts are kept per-machine in a small
# timestamp log under $TMPDIR; entries older than the window are pruned on
# every call, so the limiter self-heals and needs no cleanup cron.

LIMIT=20      # max qualifying calls ...
WINDOW=60     # ... within this many seconds

INPUT=$(cat)

TOOL_NAME=$(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null)
[[ -z "$TOOL_NAME" ]] && exit 0

# Lowercase the tool name once for case-insensitive MCP matching.
TOOL_LC=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')

relevant=0
case "$TOOL_NAME" in
  Bash)
    COMMAND=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null)
    # A mysql/mariadb token being used to RUN something: followed by an
    # execute flag (-e / --execute) or a heredoc (<<). Mirrors db-guard's
    # client detection so incidental mentions (echo, grep, prose) pass.
    CLIENT_RE='\b(mysql|mariadb)\b[^;&|]*([[:space:]](-e|--execute)([[:space:]=]|['\''"]|$)|<<)'
    echo "$COMMAND" | grep -qE "$CLIENT_RE" && relevant=1
    ;;
  *)
    # Any MySQL MCP tool, e.g. mcp__mysql__query, mcp__mcp_mysql__exec.
    [[ "$TOOL_LC" == mcp__*mysql* ]] && relevant=1
    ;;
esac

[[ "$relevant" -eq 1 ]] || exit 0

now=$(date +%s)
cutoff=$((now - WINDOW))

STATE_DIR="${TMPDIR:-/tmp}/claude-mysql-ratelimit"
STATE_FILE="$STATE_DIR/calls.log"
mkdir -p "$STATE_DIR" 2>/dev/null

# Read existing timestamps that are still inside the window.
recent=()
if [[ -f "$STATE_FILE" ]]; then
  while read -r ts; do
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    (( ts >= cutoff )) && recent+=("$ts")
  done < "$STATE_FILE"
fi

count=${#recent[@]}

if (( count >= LIMIT )); then
  # Persist the pruned window (do not record the blocked attempt).
  printf '%s\n' "${recent[@]}" > "$STATE_FILE"
  retry_after=$(( recent[0] + WINDOW - now ))
  (( retry_after < 1 )) && retry_after=1
  echo "BLOCKED: MySQL rate limit reached ($LIMIT calls / ${WINDOW}s)." >&2
  echo "Wait ~${retry_after}s before the next mysql/mcp_mysql call, or batch your queries." >&2
  exit 2
fi

# Record this call and persist the pruned + appended window.
recent+=("$now")
printf '%s\n' "${recent[@]}" > "$STATE_FILE"
exit 0
