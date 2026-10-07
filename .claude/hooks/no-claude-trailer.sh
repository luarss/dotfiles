#!/usr/bin/env bash

INPUT=$(cat)

[[ "$INPUT" == *[Cc]o-[Aa]uthored-[Bb]y* || "$INPUT" == *noreply@anthropic.com* ]] || exit 0

COMMAND=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

TRAILER_PATTERN='(^|["'\''])[[:space:]]*co-authored-by:[[:space:]]*(claude|[^"'\'']*noreply@anthropic\.com)'

if grep -qiE "$TRAILER_PATTERN" <<<"$COMMAND"; then
  echo "BLOCKED: commit message contains a Claude attribution trailer." >&2
  echo "Remove the 'Co-Authored-By: Claude <noreply@anthropic.com>' line and retry the commit." >&2
  exit 2
fi

exit 0
