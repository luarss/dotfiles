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

@test "allows an armed session in an allowed workspace" {
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "denies when not armed" {
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

@test "denies outside the allowed workspace root" {
  export GROK_WORKSPACE_ROOT="/etc"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside"* ]]
}

@test "denies a sibling directory sharing the root prefix" {
  export GROK_WORKSPACE_ROOT="$HOME/workshop"
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
}

@test "denies when the workspace root is unknown" {
  unset GROK_WORKSPACE_ROOT
  run_guard "$(bash_event "ls")"
  [ "$status" -eq 2 ]
}

@test "falls back to workspaceRoot from the event" {
  unset GROK_WORKSPACE_ROOT
  run_guard "$(jq -cn --arg root "$HOME/work/repo" '{toolName: "Bash", workspaceRoot: $root, toolInput: {command: "ls"}}')"
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
