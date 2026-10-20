#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/notify-feedback.sh"
  CAPTURE="$BATS_TEST_TMPDIR/capture"
  STUB="$BATS_TEST_TMPDIR/notify-stub"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$1" "$2" > "%s"\n' "$CAPTURE" > "$STUB"
  chmod +x "$STUB"
  export CLAUDE_NOTIFY_CMD="$STUB"
}

@test "notifies with message and project name" {
  run bash "$HOOK" <<<'{"message":"Claude needs your permission to use Bash","cwd":"/Users/me/work/dotfiles"}'
  [ "$status" -eq 0 ]
  [ "$(cat "$CAPTURE")" = "Claude Code — dotfiles|Claude needs your permission to use Bash" ]
}

@test "falls back to default message without project" {
  run bash "$HOOK" <<<'{}'
  [ "$status" -eq 0 ]
  [ "$(cat "$CAPTURE")" = "Claude Code|Claude Code needs your input" ]
}

@test "passes quotes through untouched" {
  run bash "$HOOK" <<<'{"message":"say \"hi\" & '\''bye'\''"}'
  [ "$status" -eq 0 ]
  [ "$(cat "$CAPTURE")" = "Claude Code|say \"hi\" & 'bye'" ]
}

@test "never fails when notifier errors" {
  export CLAUDE_NOTIFY_CMD=false
  run bash "$HOOK" <<<'{"message":"x"}'
  [ "$status" -eq 0 ]
}

@test "tolerates invalid json" {
  run bash "$HOOK" <<<'not json'
  [ "$status" -eq 0 ]
}
