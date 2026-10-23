#!/bin/bash -eu

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="$(id -un)"
SCREENSHARING_LABEL="system/com.apple.screensharing"
SCREENSHARING_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"
ACCESS_GROUP="com.apple.access_screensharing"
SOCKETFILTER="${REMOTE_ACCESS_SOCKETFILTER:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
TAILSCALE_CLI="${REMOTE_ACCESS_TAILSCALE_CLI:-}"
TAILSCALE_APP_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

failures=0

report() { printf '%-5s %s\n' "$1" "$2"; }
pass() { report OK "$1"; }
fail() { report FAIL "$1"; failures=$((failures + 1)); }
warn() { report WARN "$1"; }

usage() {
  echo "Usage: $(basename "$0") [check|apply]" >&2
  echo "  check  report whether this Mac is ready for Tailscale + Screen Sharing (default, read-only)" >&2
  echo "  apply  enable Screen Sharing for $OWNER only, disable AC sleep, enable the firewall, then check" >&2
}

run_privileged() {
  report RUN "sudo $*"
  sudo "$@"
}

resolve_tailscale_cli() {
  if [ -n "$TAILSCALE_CLI" ]; then
    echo "$TAILSCALE_CLI"
    return 0
  fi
  if command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
    return 0
  fi
  if [ -x "$TAILSCALE_APP_CLI" ]; then
    echo "$TAILSCALE_APP_CLI"
  fi
  return 0
}

screen_sharing_running() {
  launchctl print "$SCREENSHARING_LABEL" >/dev/null 2>&1
}

access_group_members() {
  dscl . -read "/Groups/$ACCESS_GROUP" GroupMembership 2>/dev/null | sed 's/^GroupMembership: *//'
}

ac_sleep_minutes() {
  pmset -g custom | awk '/^AC Power:/ { in_ac = 1; next } /^Battery Power:/ { in_ac = 0 } in_ac && $1 == "sleep" { print $2; exit }'
}

apply_screen_sharing() {
  run_privileged launchctl enable "$SCREENSHARING_LABEL"
  if ! screen_sharing_running; then
    run_privileged launchctl bootstrap system "$SCREENSHARING_PLIST" || true
  fi
}

apply_access_group() {
  if ! dseditgroup -o read "$ACCESS_GROUP" >/dev/null 2>&1; then
    run_privileged dseditgroup -o create -q "$ACCESS_GROUP"
  fi
  run_privileged dseditgroup -o edit -a "$OWNER" -t user "$ACCESS_GROUP"
}

apply_all() {
  report RUN "sudo -v"
  sudo -v
  apply_screen_sharing
  apply_access_group
  run_privileged pmset -c sleep 0
  run_privileged "$SOCKETFILTER" --setglobalstate on
}

check_screen_sharing() {
  if screen_sharing_running; then
    pass "Screen Sharing enabled"
  else
    fail "Screen Sharing not enabled"
  fi
}

check_access_group() {
  local members
  members="$(access_group_members)"
  if [ "$members" = "$OWNER" ]; then
    pass "Screen Sharing restricted to $OWNER"
  else
    fail "Screen Sharing access group is '${members:-missing}', expected only '$OWNER'"
  fi
}

check_sleep() {
  local minutes
  minutes="$(ac_sleep_minutes)"
  if [ "$minutes" = "0" ]; then
    pass "System sleep disabled on AC power"
  else
    fail "System sleeps after ${minutes:-unknown} min on AC power"
  fi
}

check_firewall() {
  if "$SOCKETFILTER" --getglobalstate | grep -q "enabled"; then
    pass "Application firewall enabled"
  else
    fail "Application firewall disabled"
  fi
}

check_screen_lock() {
  if sysadminctl -screenLock status 2>&1 | grep -q "screenLock delay is immediate"; then
    pass "Screen locks immediately"
  else
    fail "Screen lock delay is not immediate (System Settings > Lock Screen)"
  fi
}

check_filevault() {
  if fdesetup status | grep -q "FileVault is On"; then
    pass "FileVault on"
  else
    fail "FileVault off (enable in System Settings > Privacy & Security)"
  fi
}

check_tailscale() {
  local cli state dns
  cli="$(resolve_tailscale_cli)"
  if [ -z "$cli" ]; then
    fail "Tailscale not installed (run: brew bundle)"
    return 0
  fi
  state="$("$cli" status --json 2>/dev/null | jq -r '.BackendState // empty' || true)"
  if [ "$state" != "Running" ]; then
    fail "Tailscale not connected (state: ${state:-unknown}); open Tailscale and sign in"
    return 0
  fi
  dns="$("$cli" status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
  pass "Tailscale connected"
  report INFO "connect from your other device with: vnc://$dns"
}

warn_if_laptop() {
  if pmset -g batt | grep -q "InternalBattery"; then
    warn "Laptop: a closed lid sleeps the machine regardless of pmset unless an external display is attached"
  fi
}

run_checks() {
  check_screen_sharing
  check_access_group
  check_sleep
  check_firewall
  check_screen_lock
  check_filevault
  check_tailscale
  warn_if_laptop
}

main() {
  local mode="${1:-check}"
  case "$mode" in
    check | apply) ;;
    *) usage; exit 2 ;;
  esac

  if [ "$(uname)" != "Darwin" ]; then
    report SKIP "remote access setup (not macOS)"
    return 0
  fi
  if ! "$DOTFILES/install.sh" --is-work-machine; then
    report SKIP "remote access setup (non-work machine)"
    return 0
  fi

  [ "$mode" = "apply" ] && apply_all
  run_checks
  [ "$failures" -eq 0 ]
}

main "$@"
