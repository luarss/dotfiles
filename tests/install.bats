#!/usr/bin/env bats
# Tests for install.sh bootstrap script
#
# install.sh is a macOS/zsh setup and no-ops entirely on Linux. CI runs on
# Linux, so the default (unmocked) case exercises the Linux skip path. The one
# macOS test below mocks `uname` to Darwin to cover the real install path.

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

# --- Linux: install is a full no-op ---

@test "install_no_ops_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  install (Linux is not a supported target"* ]]
  # "Done." only prints at the end of a real install; the skip returns before it
  [[ "$output" != *"Done."* ]]
}

@test "install_writes_nothing_to_home_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # No zsh config
  [ ! -e "$HOME/.zshenv" ]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -e "$HOME/.claude-profiles.zsh" ]

  # No Claude profiles / settings / skills / hooks
  [ ! -e "$HOME/.claude/settings.json" ]
  [ ! -e "$HOME/.claude/skills" ]
  [ ! -e "$HOME/.claude/hooks" ]
  [ ! -e "$HOME/.claude/scheduled-tasks" ]
  [ ! -e "$HOME/.claude/plugins/installed_plugins.json" ]
  [ ! -d "$HOME/.claude-second-profile" ]
  [ ! -d "$HOME/.claude-third-profile" ]
}

@test "install_leaves_existing_home_files_untouched_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  # Pre-existing user files must survive an install attempt on Linux
  echo "# my zshrc" > "$HOME/.zshrc"
  echo "export ZDOTDIR=/custom" > "$HOME/.zshenv"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  grep -q "# my zshrc" "$HOME/.zshrc"
  [ ! -L "$HOME/.zshrc" ]
  grep -q "export ZDOTDIR=/custom" "$HOME/.zshenv"
  [ ! -L "$HOME/.zshenv" ]
}

# --- macOS: real install path (uname mocked to Darwin) ---

@test "setup_zsh_config_symlinks_zshrc_on_macos" {
  uname() { echo "Darwin"; }
  export -f uname
  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  # On macOS, ~/.zshrc is a symlink into the dotfiles repo
  [ -L "$HOME/.zshrc" ]
  local dotfiles
  dotfiles="$(cd "$(dirname "$INSTALL_SCRIPT")" && pwd)"
  [ "$(readlink "$HOME/.zshrc")" = "$dotfiles/.zshrc" ]
  # No .zshenv is ever created (Linux ZDOTDIR path was removed)
  [ ! -e "$HOME/.zshenv" ]
}
