#!/usr/bin/env bats
# Tests for install.sh bootstrap script

setup() {
  # Create a temporary home directory for each test
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Path to the install script
  INSTALL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install.sh"

  # Store original environment
  ORIGINAL_DEEPSEEK_TOKEN="${DEEPSEEK_AUTH_TOKEN:-}"
  ORIGINAL_DASHSCOPE_TOKEN="${DASHSCOPE_AUTH_TOKEN:-}"
}

teardown() {
  # Cleanup temp directory
  rm -rf "$TEST_HOME"

  # Restore environment
  export DEEPSEEK_AUTH_TOKEN="$ORIGINAL_DEEPSEEK_TOKEN"
  export DASHSCOPE_AUTH_TOKEN="$ORIGINAL_DASHSCOPE_TOKEN"
}

@test "symlink_creates_new" {
  # .zshrc doesn't exist, should create symlink
  run bash "$INSTALL_SCRIPT"

  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$(dirname "$INSTALL_SCRIPT")/.zshrc" ]
}

@test "symlink_updates_existing" {
  # Create existing symlink to wrong target
  ln -s /tmp/wrong "$HOME/.zshrc"

  run bash "$INSTALL_SCRIPT"

  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$(dirname "$INSTALL_SCRIPT")/.zshrc" ]
}

@test "symlink_skips_regular_file" {
  # Create a regular file (not symlink)
  touch "$HOME/.zshrc"

  run bash "$INSTALL_SCRIPT"

  # Should still be a regular file, not a symlink
  [ -f "$HOME/.zshrc" ]
  [ ! -L "$HOME/.zshrc" ]

  # Should have SKIP message in output
  [[ "$output" == *"SKIP"*".zshrc"* ]]
}

@test "creates_profile_directories" {
  run bash "$INSTALL_SCRIPT"

  [ -d "$HOME/.claude-second-profile" ]
  [ -d "$HOME/.claude-third-profile" ]
}

@test "generates_settings_with_token" {
  export DEEPSEEK_AUTH_TOKEN="test-deepseek-token-12345"

  run bash "$INSTALL_SCRIPT"

  [ -f "$HOME/.claude-second-profile/settings.json" ]

  # Check that token was injected
  local token
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-second-profile/settings.json")
  [ "$token" = "test-deepseek-token-12345" ]
}

@test "generates_settings_with_dashscope_token" {
  export DASHSCOPE_AUTH_TOKEN="test-dashscope-token-67890"

  run bash "$INSTALL_SCRIPT"

  [ -f "$HOME/.claude-third-profile/settings.json" ]

  # Check that token was injected
  local token
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-third-profile/settings.json")
  [ "$token" = "test-dashscope-token-67890" ]
}

@test "generates_settings_with_empty_token" {
  # Unset tokens (or set empty)
  unset DEEPSEEK_AUTH_TOKEN
  unset DASHSCOPE_AUTH_TOKEN

  run bash "$INSTALL_SCRIPT"

  [ -f "$HOME/.claude-second-profile/settings.json" ]
  [ -f "$HOME/.claude-third-profile/settings.json" ]

  # Token should be empty string
  local token
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-second-profile/settings.json")
  [ "$token" = "" ]

  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-third-profile/settings.json")
  [ "$token" = "" ]
}

@test "settings_preserves_other_config" {
  export DEEPSEEK_AUTH_TOKEN="my-token"

  run bash "$INSTALL_SCRIPT"

  # Check that other settings are preserved from template
  local base_url
  base_url=$(jq -r '.env.ANTHROPIC_BASE_URL' "$HOME/.claude-second-profile/settings.json")
  [ "$base_url" = "https://api.deepseek.com/anthropic" ]

  local model
  model=$(jq -r '.model' "$HOME/.claude-second-profile/settings.json")
  [ "$model" = "opus" ]
}

@test "sets_git_hooks_path" {
  run bash "$INSTALL_SCRIPT"

  # Check git config was set (in the dotfiles repo, not temp home)
  local hooks_path
  hooks_path=$(git -C "$(dirname "$INSTALL_SCRIPT")" config core.hooksPath)
  [ "$hooks_path" = ".githooks" ]
}

@test "idempotent" {
  export DEEPSEEK_AUTH_TOKEN="same-token"
  export DASHSCOPE_AUTH_TOKEN="same-dashscope-token"

  # Run twice
  run bash "$INSTALL_SCRIPT"
  run bash "$INSTALL_SCRIPT"

  # Check symlinks still correct
  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$(dirname "$INSTALL_SCRIPT")/.zshrc" ]

  # Check settings still correct
  local token
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-second-profile/settings.json")
  [ "$token" = "same-token" ]

  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-third-profile/settings.json")
  [ "$token" = "same-dashscope-token" ]
}

@test "symlinks_claude_md_for_profiles" {
  run bash "$INSTALL_SCRIPT"

  # CLAUDE.md should be symlinked in each profile
  [ -L "$HOME/.claude-second-profile/CLAUDE.md" ]
  [ -L "$HOME/.claude-third-profile/CLAUDE.md" ]
}

@test "outputs_link_messages" {
  run bash "$INSTALL_SCRIPT"

  [[ "$output" == *"LINK"*".zshrc"* ]]
  [[ "$output" == *"Done."* ]]
}

@test "symlinks_claude_hooks" {
  run bash "$INSTALL_SCRIPT"

  local hooks_src
  hooks_src="$(dirname "$INSTALL_SCRIPT")/.claude/hooks"

  # Every .sh file in source should be symlinked into ~/.claude/hooks
  for hook in "$hooks_src"/*.sh; do
    [ -e "$hook" ] || continue
    local name dst
    name="$(basename "$hook")"
    dst="$HOME/.claude/hooks/$name"
    [ -L "$dst" ]
    [ "$(readlink "$dst")" = "$hook" ]
  done
}

@test "hooks_install_idempotent" {
  run bash "$INSTALL_SCRIPT"
  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local hooks_src
  hooks_src="$(dirname "$INSTALL_SCRIPT")/.claude/hooks"

  for hook in "$hooks_src"/*.sh; do
    [ -e "$hook" ] || continue
    local name dst
    name="$(basename "$hook")"
    dst="$HOME/.claude/hooks/$name"
    [ -L "$dst" ]
    [ "$(readlink "$dst")" = "$hook" ]
  done
}

@test "hooks_install_overwrites_stale_symlink" {
  # Pre-create a stale symlink pointing somewhere wrong
  mkdir -p "$HOME/.claude/hooks"
  ln -s /tmp/nonexistent-hook.sh "$HOME/.claude/hooks/symlink-memory.sh"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local expected
  expected="$(dirname "$INSTALL_SCRIPT")/.claude/hooks/symlink-memory.sh"
  [ "$(readlink "$HOME/.claude/hooks/symlink-memory.sh")" = "$expected" ]
}
