#!/usr/bin/env bats

setup() {
  local base; base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$base/scripts/remote-access-setup.sh"

  ROOT="$(mktemp -d)"
  STUBS="$ROOT/stubs"
  SUDO_LOG="$ROOT/sudo.log"
  mkdir -p "$STUBS"
  : > "$SUDO_LOG"
  export SUDO_LOG
  export HOME="$ROOT/home"
  mkdir -p "$HOME"
  export DOTFILES_ENV=/dev/null
  export DOTFILES_WORK_HOSTNAME="$(hostname -s)"
  export PATH="$STUBS:$PATH"
  OWNER="$(id -un)"

  stub uname 'echo Darwin'
  stub sudo 'echo "$*" >> "$SUDO_LOG"'
  stub launchctl 'exit 0'
  stub dseditgroup 'exit 0'
  stub dscl "echo \"GroupMembership: $OWNER\""
  stub pmset 'printf "Battery Power:\n sleep 1\nAC Power:\n sleep 0\n"'
  stub fdesetup 'echo "FileVault is On."'
  stub sysadminctl 'echo "screenLock delay is immediate"'

  export REMOTE_ACCESS_SOCKETFILTER="$STUBS/socketfilterfw"
  stub socketfilterfw 'echo "Firewall is enabled. (State = 1)"'

  export REMOTE_ACCESS_TAILSCALE_CLI="$STUBS/tailscale"
  stub tailscale 'echo "{\"BackendState\":\"Running\",\"Self\":{\"DNSName\":\"work-mac.tail1234.ts.net.\"}}"'
}

teardown() { rm -rf "$ROOT"; }

stub() {
  printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"
  chmod +x "$STUBS/$1"
}

@test "skips on a non-work machine without touching anything" {
  DOTFILES_WORK_HOSTNAME="not-this-host" run bash "$SCRIPT" apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  remote access setup (non-work machine)"* ]]
  [ ! -s "$SUDO_LOG" ]
}

@test "skips off macOS" {
  stub uname 'echo Linux'
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  remote access setup (not macOS)"* ]]
}

@test "check passes when the machine is fully configured and prints the vnc url" {
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK    Screen Sharing enabled"* ]]
  [[ "$output" == *"OK    Screen Sharing restricted to $OWNER"* ]]
  [[ "$output" == *"OK    System sleep disabled on AC power"* ]]
  [[ "$output" == *"OK    Application firewall enabled"* ]]
  [[ "$output" == *"OK    Screen locks immediately"* ]]
  [[ "$output" == *"OK    FileVault on"* ]]
  [[ "$output" == *"vnc://work-mac.tail1234.ts.net"* ]]
  [ ! -s "$SUDO_LOG" ]
}

@test "check is the default mode and never calls sudo" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$SUDO_LOG" ]
}

@test "check fails when the firewall is disabled" {
  stub socketfilterfw 'echo "Firewall is disabled. (State = 0)"'
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  Application firewall disabled"* ]]
}

@test "check fails when another user is in the screen sharing group" {
  stub dscl "echo \"GroupMembership: $OWNER someone-else\""
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  Screen Sharing access group"* ]]
}

@test "check fails when the system sleeps on AC power" {
  stub pmset 'printf "AC Power:\n sleep 10\n"'
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  System sleeps after 10 min on AC power"* ]]
}

@test "check fails when Tailscale is not connected" {
  stub tailscale 'echo "{\"BackendState\":\"NeedsLogin\"}"'
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  Tailscale not connected (state: NeedsLogin)"* ]]
}

@test "check fails when the screen lock delay is not immediate" {
  stub sysadminctl 'echo "screenLock delay is 300 seconds"'
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  Screen lock delay is not immediate"* ]]
}

@test "check fails when FileVault is off" {
  stub fdesetup 'echo "FileVault is Off."'
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL  FileVault off"* ]]
}

@test "apply enables screen sharing for the owner only, disables AC sleep and enables the firewall" {
  stub launchctl '[ "$1" = "print" ] && exit 1; exit 0'
  stub dseditgroup '[ "$2" = "read" ] && exit 1; exit 0'
  run bash "$SCRIPT" apply
  log="$(cat "$SUDO_LOG")"
  [[ "$log" == *"launchctl enable system/com.apple.screensharing"* ]]
  [[ "$log" == *"launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist"* ]]
  [[ "$log" == *"dseditgroup -o create -q com.apple.access_screensharing"* ]]
  [[ "$log" == *"dseditgroup -o edit -a $OWNER -t user com.apple.access_screensharing"* ]]
  [[ "$log" == *"pmset -c sleep 0"* ]]
  [[ "$log" == *"--setglobalstate on"* ]]
}

@test "apply does not recreate an existing access group or re-bootstrap a running service" {
  run bash "$SCRIPT" apply
  [ "$status" -eq 0 ]
  log="$(cat "$SUDO_LOG")"
  [[ "$log" != *"dseditgroup -o create"* ]]
  [[ "$log" != *"launchctl bootstrap"* ]]
}

@test "unknown mode exits 2 with usage" {
  run bash "$SCRIPT" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}
