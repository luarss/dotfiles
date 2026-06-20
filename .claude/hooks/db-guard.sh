#!/usr/bin/env bash
# DB Guard — PreToolUse hook (matcher: Bash)
# Blocks destructive SQL run through the mysql / mariadb / psql CLIs:
# DROP TABLE/DATABASE/SCHEMA, TRUNCATE, DELETE without WHERE, ALTER TABLE ... DROP.
#
# Wired in settings.base.json (all profiles). Exit codes: 0 = allow, 2 = block.
#
# Scope: inspects the Bash command string, so it only sees SQL passed inline
# (e.g. `psql -c '...'`, `mysql -e '...'`, heredocs). SQL in a file run via
# `psql -f script.sql` is NOT inspected — the guard can't read the file.
#
# Adapted from sangrokjung/claude-forge hooks/db-guard.sh (originally a Supabase
# MCP guard); retargeted to the Bash tool + local SQL clients, using jq to match
# this repo's convention.

INPUT=$(cat)

# Fast pre-filter: skip jq if no SQL client keyword appears in the raw payload.
# jq startup costs ~25ms; this makes the no-op path nearly free.
[[ "$INPUT" == *mysql* || "$INPUT" == *mariadb* || "$INPUT" == *psql* ]] || exit 0

COMMAND=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Only guard when a SQL client is actually being used to RUN a statement:
# a mysql/mariadb/psql token followed (within the same command segment) by an
# execute flag (-e / --execute / -c / --command) or a heredoc (<<). This is
# what `mysql -e '...'` / `psql -c '...'` look like, while incidental mentions
# (commit messages, `echo mysql ...`, `grep psql`, prose) carry no such flag
# and pass through untouched.
CLIENT_RE='\b(mysql|mariadb|psql)\b[^;&|]*([[:space:]](-e|-c|--execute|--command)([[:space:]=]|['\''"]|$)|<<)'
echo "$COMMAND" | grep -qE "$CLIENT_RE" || exit 0

COMMAND_UPPER=$(echo "$COMMAND" | tr '[:lower:]' '[:upper:]')

block() {
  echo "BLOCKED: $1" >&2
  echo "Command: ${COMMAND:0:200}" >&2
  exit 2
}

# DROP TABLE/DATABASE/SCHEMA
echo "$COMMAND_UPPER" | grep -qE '\bDROP[[:space:]]+(TABLE|DATABASE|SCHEMA)\b' \
  && block "DROP statement detected"

# TRUNCATE
echo "$COMMAND_UPPER" | grep -qE '\bTRUNCATE\b' \
  && block "TRUNCATE statement detected"

# DELETE without WHERE
if echo "$COMMAND_UPPER" | grep -qE '\bDELETE[[:space:]]+FROM\b' \
  && ! echo "$COMMAND_UPPER" | grep -qE '\bWHERE\b'; then
  block "DELETE without WHERE clause"
fi

# ALTER TABLE ... DROP (destructive schema change)
echo "$COMMAND_UPPER" | grep -qE '\bALTER[[:space:]]+TABLE\b.*\bDROP\b' \
  && block "ALTER TABLE DROP detected"

# Safe — allow.
exit 0
