#!/usr/bin/env bats

setup() {
  GUARD="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/grok/hooks/identity-guard.sh"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export GROK_WORKSPACE_ROOT="$HOME/work/repo"
  export GROK_GUARD_ARMED_FILE="$HOME/armed"
  ioreg() { echo '"CGSSessionOnConsoleKey" = Yes'; }
  export -f ioreg
  touch "$GROK_GUARD_ARMED_FILE"
}

teardown() {
  rm -rf "$TEST_HOME"
}

run_guard() {
  run bash "$GUARD" <<<"$1"
}

bash_event() {
  jq -cn --arg command "$1" '{hookEventName: "PreToolUse", toolName: "Bash", toolInput: {command: $command}}'
}

@test "non-office user is allowed when armed" {
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-office user is denied when not armed" {
  rm "$GROK_GUARD_ARMED_FILE"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"decision":"deny"'*"not armed"* ]]
}

@test "denies when arming has expired" {
  export GROK_GUARD_ARMED_TTL_SECONDS=0
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"arming expired"* ]]
}

@test "office user runs unattended without arming" {
  export GROK_GUARD_OFFICE_USERS="someone-else $(id -un)"
  rm "$GROK_GUARD_ARMED_FILE"
  ioreg() { echo '"CGSSessionScreenIsLocked" = Yes'; }
  export -f ioreg
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "office user is denied outside the allowed workspace root" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)"
  export GROK_WORKSPACE_ROOT="/etc"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside"* ]]
}

@test "office user is denied a sibling directory sharing the root prefix" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)"
  export GROK_WORKSPACE_ROOT="$HOME/workshop"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
}

@test "office user is denied when the workspace root is unknown" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)"
  unset GROK_WORKSPACE_ROOT
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
}

@test "office user falls back to workspaceRoot from the event" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)"
  unset GROK_WORKSPACE_ROOT
  run_guard "$(jq -cn --arg root "$HOME/work/repo" '{toolName: "Bash", workspaceRoot: $root, toolInput: {command: "ls"}}')"
  [ "$status" -eq 0 ]
}

@test "office user cannot touch grok hooks" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)"
  run_guard "$(bash_event "rm ~/.grok/hooks/identity-guard.sh")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"protected"* ]]
}

@test "username prefix does not count as an office user" {
  export GROK_GUARD_OFFICE_USERS="$(id -un)x"
  rm "$GROK_GUARD_ARMED_FILE"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not armed"* ]]
}

@test "armed non-office user may work outside the office workspace root" {
  export GROK_WORKSPACE_ROOT="$HOME/projects/repo"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 0 ]
}

@test "denies touching the arming file or grok hooks" {
  run_guard "$(bash_event "touch ~/.grok/armed")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"protected"* ]]
}

@test "denies while the screen is locked" {
  ioreg() { echo '"CGSSessionScreenIsLocked" = Yes'; }
  export -f ioreg
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"screen is locked"* ]]
}

@test "fails closed on malformed event json" {
  run_guard "not json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"identity guard error"* ]]
}
