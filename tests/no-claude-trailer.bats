#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/no-claude-trailer.sh"
}

run_command() {
  local payload
  payload=$(jq -nc --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}')
  run bash "$HOOK" <<<"$payload"
}

@test "blocks git commit with Claude co-author trailer" {
  run_command 'git commit -q -m "fix: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"'
  [ "$status" -eq 2 ]
  [[ "$output" == *BLOCKED* ]]
}

@test "blocks rtk-wrapped git commit with trailer" {
  run_command 'rtk git commit -m "fix: x" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"'
  [ "$status" -eq 2 ]
}

@test "blocks git -C commit with trailer" {
  run_command 'git -C /tmp/repo commit -m "fix: x" -m "co-authored-by: claude"'
  [ "$status" -eq 2 ]
}

@test "blocks heredoc commit message with anthropic noreply address" {
  run_command $'git commit -F - <<EOF\nfix: x\n\nCo-authored-by: Bot <noreply@anthropic.com>\nEOF'
  [ "$status" -eq 2 ]
}

@test "allows git commit without trailer" {
  run_command 'git commit -m "fix: x"'
  [ "$status" -eq 0 ]
}

@test "allows human co-author trailer" {
  run_command 'git commit -m "fix: x" -m "Co-Authored-By: Jane <jane@example.com>"'
  [ "$status" -eq 0 ]
}

@test "allows commit message that only mentions the trailer in prose" {
  run_command $'git commit -F - <<EOF\nfeat: x\n\nSubagents can type a Co-Authored-By: Claude trailer themselves.\nEOF'
  [ "$status" -eq 0 ]
}

@test "blocks trailer inside a multi-line -m message" {
  run_command $'git commit -m "fix: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>"'
  [ "$status" -eq 2 ]
}

@test "allows payload without a command" {
  run bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{}}'
  [ "$status" -eq 0 ]
}

@test "settings.base.json wires the hook for git commit variants" {
  run jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("no-claude-trailer")) | .if' "$REPO_ROOT/settings.base.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(git commit *)"* ]]
  [[ "$output" == *"Bash(rtk git commit *)"* ]]
  [[ "$output" == *"Bash(git -C * commit *)"* ]]
}

@test "default profile overrides also wire the hook before rtk" {
  run jq -r '.[] | select(.dir == ".claude") | .overrides.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | map(.command) | (map(contains("no-claude-trailer")) | index(true)) < (map(contains("rtk-hook")) | index(true))' "$REPO_ROOT/providers.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
