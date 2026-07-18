#!/usr/bin/env bats
# Tests for install.sh bootstrap script
#
# install.sh is primarily a macOS/zsh setup. On Linux (e.g. the bwrap sandbox
# used by remote/orchestrated sessions) it skips the multi-profile machinery
# (no zsh wrapper there to reach a second/third profile) but still installs
# ~/.zshrc plus the Claude Code default profile: settings.json, hooks, skills,
# commands. CI runs on Linux, so the default (unmocked) case exercises that
# scoped path. The one macOS test below mocks `uname` to Darwin to cover the
# full install path (all profiles + zsh wrapper).

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

# --- Linux: scoped install (default profile only, no zsh/ZDOTDIR) ---

@test "install_completes_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GEN   $HOME/.claude/settings.json (default)"* ]]
  [[ "$output" == *"Done."* ]]
}

@test "install_writes_only_default_profile_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # ~/.zshrc IS installed on Linux (as a real file, not a symlink — see
  # setup_zsh_config_writes_real_zshrc_file_on_linux for why), but the
  # multi-profile wrapper stays macOS-only (no zsh `cl` dispatcher to reach it)
  [ ! -e "$HOME/.zshenv" ]
  [ -e "$HOME/.zshrc" ]
  [ ! -L "$HOME/.zshrc" ]
  [ ! -e "$HOME/.claude-profiles.zsh" ]

  # Default Claude profile IS installed
  [ -e "$HOME/.claude/settings.json" ]
  [ -d "$HOME/.claude/skills" ]
  [ -d "$HOME/.claude/hooks" ]
  [ -L "$HOME/.claude/hooks/db-guard.sh" ]

  # ...but not the macOS-only extras: other profiles, plugin lock, work-only routines
  [ ! -d "$HOME/.claude-second-profile" ]
  [ ! -d "$HOME/.claude-third-profile" ]
  [ ! -e "$HOME/.claude/scheduled-tasks" ]
  [ ! -e "$HOME/.claude/plugins/installed_plugins.json" ]
}

@test "install_default_profile_settings_on_linux_has_hooks_and_sonnet" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # Personal (non-work) machine: model forced to sonnet regardless of OS
  [ "$(jq -r '.model' "$HOME/.claude/settings.json")" = "sonnet" ]

  # The 5-hook PreToolUse chain + symlink-memory PostToolUse are present...
  [ "$(jq '[.hooks.PreToolUse[].hooks[].command] | length' "$HOME/.claude/settings.json")" -eq 6 ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].command' "$HOME/.claude/settings.json")" = '"bash ~/.claude/hooks/symlink-memory.sh"' ]

  # ...but the deepseek-only guard must NOT be wired into the default profile
  # (it belongs solely to the deepseek provider's overrides — see providers.json)
  [ "$(jq -r '.hooks | has("UserPromptSubmit")' "$HOME/.claude/settings.json")" = "false" ]
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

@test "setup_zsh_config_writes_real_zshrc_file_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # A real file, NOT a symlink: bwrap (the sandbox this path targets) follows
  # symlinks when precomputing tmpfs bind-mount points, so a symlink whose
  # target isn't already in that list fails with ENOENT. A real file with a
  # source line only needs bwrap to resolve two concrete paths.
  [ -f "$HOME/.zshrc" ]
  [ ! -L "$HOME/.zshrc" ]
  local dotfiles
  dotfiles="$(cd "$(dirname "$INSTALL_SCRIPT")" && pwd)"
  grep -qF "source \"$dotfiles/.zshrc\"" "$HOME/.zshrc"

  # Re-running install.sh regenerates the same source-file, rather than
  # getting skipped as a foreign file (idempotent re-install)
  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.zshrc" ]
  grep -qF "source \"$dotfiles/.zshrc\"" "$HOME/.zshrc"
}

@test "setup_zsh_config_excludes_rtk_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  # RTK.md/rtk are Homebrew/macOS-only — they must stay out of the Linux path
  # even though ~/.zshrc itself is now installed there
  [ ! -e "$HOME/.claude/RTK.md" ]
  [[ "$(cat "$HOME/.claude/CLAUDE.md" 2>/dev/null)" != *RTK.md* ]]
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
