#!/usr/bin/env bash
set -u

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
message=$(jq -r '.message // "Claude Code needs your input"' <<<"$payload" 2>/dev/null)
project=$(basename "$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)")
title="Claude Code${project:+ — $project}"

if [ -n "${CLAUDE_NOTIFY_CMD:-}" ]; then
  $CLAUDE_NOTIFY_CMD "$title" "$message" || true
  exit 0
fi

command -v osascript >/dev/null 2>&1 || exit 0

osascript \
  -e 'on run argv' \
  -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Glass"' \
  -e 'end run' \
  "$title" "$message" >/dev/null 2>&1 || true
exit 0
