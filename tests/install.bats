#!/usr/bin/env bats
# Tests for install.sh bootstrap script

setup() {
  # Create a temporary home directory for each test
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Path to the install script
  INSTALL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install.sh"

  # Isolate from the repo's real .env so tokens come only from the test env.
  # /dev/null is not a regular file, so install.sh skips sourcing it.
  export DOTFILES_ENV=/dev/null

  # Skip the npm ci for pinned tools (network-dependent, per-test $HOME)
  export DOTFILES_SKIP_NODE_TOOLS=1

  # Store original environment
  ORIGINAL_DEEPSEEK_TOKEN="${DEEPSEEK_AUTH_TOKEN:-}"
  ORIGINAL_XIAOMI_TOKEN="${XIAOMI_AUTH_TOKEN:-}"
}

teardown() {
  # Cleanup temp directory
  rm -rf "$TEST_HOME"

  # Restore environment
  export DEEPSEEK_AUTH_TOKEN="$ORIGINAL_DEEPSEEK_TOKEN"
  export XIAOMI_AUTH_TOKEN="$ORIGINAL_XIAOMI_TOKEN"
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

@test "generates_settings_with_xiaomi_token" {
  export XIAOMI_AUTH_TOKEN="test-xiaomi-token-67890"

  run bash "$INSTALL_SCRIPT"

  [ -f "$HOME/.claude-third-profile/settings.json" ]

  # Check that token was injected
  local token
  token=$(jq -r '.env.ANTHROPIC_AUTH_TOKEN' "$HOME/.claude-third-profile/settings.json")
  [ "$token" = "test-xiaomi-token-67890" ]
}

@test "generates_settings_with_empty_token" {
  # Unset tokens (or set empty)
  unset DEEPSEEK_AUTH_TOKEN
  unset XIAOMI_AUTH_TOKEN

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
  export XIAOMI_AUTH_TOKEN="same-xiaomi-token"

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
  [ "$token" = "same-xiaomi-token" ]
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

@test "sonnet_switch_applied_on_personal_laptop" {
  # Mock hostname to return something other than the work hostname
  hostname() { echo "personal-macbook-pro"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"

  local model
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "sonnet" ]
  [[ "$output" == *"SET"*"model -> sonnet (personal)"* ]]
}

@test "sonnet_switch_skipped_on_work_machine" {
  # Mock hostname to return the default work hostname
  hostname() { echo "Shuis-MacBook-Air"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"

  local expected model
  expected=$(jq -r '.default.overrides.model' "$(dirname "$INSTALL_SCRIPT")/providers.json")
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "$expected" ]
  [[ "$output" == *"SKIP"*"keeping $expected"* ]]
}

@test "sonnet_switch_respects_custom_work_hostname" {
  # Custom work hostname via env var
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"

  hostname() { echo "custom-corp-laptop"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"

  local expected model
  expected=$(jq -r '.default.overrides.model' "$(dirname "$INSTALL_SCRIPT")/providers.json")
  model=$(jq -r '.model' "$HOME/.claude/settings.json")
  [ "$model" = "$expected" ]
  [[ "$output" == *"SKIP"*"keeping $expected"* ]]
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

@test "symlinks_claude_skills" {
  run bash "$INSTALL_SCRIPT"

  local skills_src
  skills_src="$(dirname "$INSTALL_SCRIPT")/skills"

  # Every skill directory in source should be symlinked into ~/.claude/skills
  for skill_dir in "$skills_src"/*/; do
    [ -e "$skill_dir" ] || continue
    local name dst
    name="$(basename "$skill_dir")"
    dst="$HOME/.claude/skills/$name"
    [ -L "$dst" ]
    [ "$(readlink "$dst")" = "$skill_dir" ]
  done
}

@test "skills_install_overwrites_stale_symlink" {
  # Pre-create a stale symlink where a skill should land
  mkdir -p "$HOME/.claude/skills"
  ln -s /tmp/nonexistent-skill "$HOME/.claude/skills/obsidian-journal"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local expected
  expected="$(dirname "$INSTALL_SCRIPT")/skills/obsidian-journal/"
  [ "$(readlink "$HOME/.claude/skills/obsidian-journal")" = "$expected" ]
}

@test "routines_installed_on_work_machine" {
  hostname() { echo "Shuis-MacBook-Air"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local routines_src
  routines_src="$(dirname "$INSTALL_SCRIPT")/routines"

  # Every routine directory in source should be symlinked into ~/.claude/scheduled-tasks
  for routine_dir in "$routines_src"/*/; do
    [ -e "$routine_dir" ] || continue
    local name dst
    name="$(basename "$routine_dir")"
    dst="$HOME/.claude/scheduled-tasks/$name"
    [ -L "$dst" ]
    [ "$(readlink "$dst")" = "$routine_dir" ]
  done
}

@test "routines_skipped_on_personal_laptop" {
  hostname() { echo "personal-macbook-pro"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # No routines should be applied at all on a non-work machine
  [ ! -e "$HOME/.claude/scheduled-tasks" ]
  [[ "$output" == *"SKIP  routines (non-work machine)"* ]]
}

@test "routines_respect_custom_work_hostname" {
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"
  hostname() { echo "custom-corp-laptop"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local routines_src
  routines_src="$(dirname "$INSTALL_SCRIPT")/routines"
  for routine_dir in "$routines_src"/*/; do
    [ -e "$routine_dir" ] || continue
    [ -L "$HOME/.claude/scheduled-tasks/$(basename "$routine_dir")" ]
  done
}

@test "routines_install_skips_real_dir" {
  # A machine-local (real) routine dir must be left untouched
  hostname() { echo "Shuis-MacBook-Air"; }
  export -f hostname

  # Use whichever routine happens to exist in the repo, so the test
  # survives /sync-routines renaming or removing routines
  local routine_name
  routine_name="$(basename "$(find "$(dirname "$INSTALL_SCRIPT")/routines" -mindepth 1 -maxdepth 1 -type d | head -1)")"
  [ -n "$routine_name" ]

  mkdir -p "$HOME/.claude/scheduled-tasks/$routine_name"
  touch "$HOME/.claude/scheduled-tasks/$routine_name/local-marker"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  [ ! -L "$HOME/.claude/scheduled-tasks/$routine_name" ]
  [ -f "$HOME/.claude/scheduled-tasks/$routine_name/local-marker" ]
  [[ "$output" == *"SKIP"*"$routine_name (exists and is not a symlink)"* ]]
}

@test "routines_prune_dangling_symlinks" {
  # A symlink into routines/ whose source dir was deleted (routine removed
  # server-side, pruned by /sync-routines) must be cleaned up
  hostname() { echo "Shuis-MacBook-Air"; }
  export -f hostname

  local routines_src
  routines_src="$(dirname "$INSTALL_SCRIPT")/routines"

  mkdir -p "$HOME/.claude/scheduled-tasks"
  ln -s "$routines_src/deleted-routine/" "$HOME/.claude/scheduled-tasks/deleted-routine"
  # Dangling symlinks NOT pointing into routines/ are none of our business
  ln -s "$HOME/nonexistent-target" "$HOME/.claude/scheduled-tasks/unrelated-dangling"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  [ ! -L "$HOME/.claude/scheduled-tasks/deleted-routine" ]
  [[ "$output" == *"PRUNE"*"deleted-routine"* ]]
  [ -L "$HOME/.claude/scheduled-tasks/unrelated-dangling" ]
}

@test "skills_install_skips_real_dir" {
  # A manually installed (real) skill dir must be left untouched
  mkdir -p "$HOME/.claude/skills/obsidian-journal"
  touch "$HOME/.claude/skills/obsidian-journal/local-marker"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  [ ! -L "$HOME/.claude/skills/obsidian-journal" ]
  [ -f "$HOME/.claude/skills/obsidian-journal/local-marker" ]
  [[ "$output" == *"SKIP"*"obsidian-journal (exists and is not a symlink)"* ]]
}
