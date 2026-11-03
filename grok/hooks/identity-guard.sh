#!/usr/bin/env bash
set -uo pipefail

deny() {
  printf '{"decision":"deny","reason":"%s"}\n' "$1"
  exit 2
}

trap 'deny "identity guard error"' ERR

ARMED_FILE="${GROK_GUARD_ARMED_FILE:-$HOME/.grok/armed}"
ARMED_TTL_SECONDS="${GROK_GUARD_ARMED_TTL_SECONDS:-3600}"
ALLOWED_ROOT="${GROK_GUARD_ALLOWED_ROOT:-$HOME/work}"
OFFICE_USERS="${GROK_GUARD_OFFICE_USERS:-}"

screen_is_locked() {
  ioreg -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked" = Yes'
}

is_office_user() {
  [[ -n "$OFFICE_USERS" && " $OFFICE_USERS " == *" $(id -un) "* ]]
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

event=$(cat)
tool_input=$(jq -c '.toolInput // {}' <<<"$event")
workspace_root="${GROK_WORKSPACE_ROOT:-$(jq -r '.workspaceRoot // empty' <<<"$event")}"

[[ "$tool_input" != *".grok"* ]] || deny "grok hooks and arming are protected"

if is_office_user; then
  [[ "$workspace_root" == "$ALLOWED_ROOT" || "$workspace_root" == "$ALLOWED_ROOT/"* ]] \
    || deny "workspace '${workspace_root:-unknown}' is outside $ALLOWED_ROOT"
  exit 0
fi

! screen_is_locked || deny "screen is locked: nobody is at this Mac"
[[ -f "$ARMED_FILE" ]] || deny "not armed: run 'touch ~/.grok/armed' at this Mac"
armed_mtime=$(file_mtime "$ARMED_FILE")
[[ "$armed_mtime" =~ ^[0-9]+$ && "$ARMED_TTL_SECONDS" =~ ^[0-9]+$ ]] || deny "cannot read arming time"
(( $(date +%s) - armed_mtime < ARMED_TTL_SECONDS )) || deny "arming expired: run 'touch ~/.grok/armed' at this Mac"
exit 0
