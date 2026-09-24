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
  # Skip zsh plugins clone (network-dependent, per-test $HOME)
  export DOTFILES_SKIP_ZSH_PLUGINS=1

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

  # ...but not the macOS-only extras: other profiles, plugin lock
  [ ! -d "$HOME/.claude-second-profile" ]
  [ ! -d "$HOME/.claude-third-profile" ]
  [ ! -e "$HOME/.claude/plugins/installed_plugins.json" ]
}

@test "install_default_profile_settings_on_linux_has_hooks_and_sonnet" {
  uname() { echo "Linux"; }
  # Mock a non-work hostname so the sonnet switch fires even when the test
  # suite runs on the work machine itself
  hostname() { echo "personal-linux-box"; }
  export -f uname hostname

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

@test "weekly_cutover_agent_skipped_on_non_work_machine" {
  uname() { echo "Darwin"; }
  hostname() { echo "personal-macbook-pro"; }
  export -f uname hostname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  weekly-cutover agent (non-work machine)"* ]]
  # No plist may be generated for any label on a non-work machine
  [ ! -e "$HOME/Library/LaunchAgents/com.$(id -un).weekly-cutover.plist" ]
}

@test "weekly_cutover_agent_installed_on_work_machine_with_vault_tool" {
  uname() { echo "Darwin"; }
  hostname() { echo "custom-corp-laptop"; }
  # Stub launchctl/trivy so the test is hermetic: never touches the real
  # launchd job or the network (launchctl unload by label would otherwise
  # unload the REAL agent when tests run on the work machine itself)
  launchctl() { return 0; }
  trivy() { return 0; }
  export -f uname hostname launchctl trivy
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"

  # The agent additionally requires the vault's new-week.sh to exist
  mkdir -p "$HOME/work/notes/NUS-Enterprise/tools"
  touch "$HOME/work/notes/NUS-Enterprise/tools/new-week.sh"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]

  local plist="$HOME/Library/LaunchAgents/com.$(id -un).weekly-cutover.plist"
  [ -f "$plist" ]
  grep -q "new-week.sh" "$plist"
  grep -q "<string>--next</string>" "$plist"
  # Wednesday 14:00 schedule
  grep -q "<key>Weekday</key><integer>3</integer><key>Hour</key><integer>14</integer>" "$plist"
}

@test "weekly_cutover_agent_skipped_on_work_machine_without_vault_tool" {
  uname() { echo "Darwin"; }
  hostname() { echo "custom-corp-laptop"; }
  launchctl() { return 0; }
  trivy() { return 0; }
  export -f uname hostname launchctl trivy
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP  weekly-cutover agent (no "* ]]
  [ ! -e "$HOME/Library/LaunchAgents/com.$(id -un).weekly-cutover.plist" ]
}

@test "install_agy_settings_merges_overrides_and_preserves_app_state" {
  uname() { echo "Darwin"; }
  hostname() { echo "personal-macbook-pro"; }
  export -f uname hostname

  # Simulate app-managed state that already exists before install.sh runs
  mkdir -p "$HOME/.gemini/antigravity-cli"
  cat > "$HOME/.gemini/antigravity-cli/settings.json" <<'EOF'
{
  "gcp": { "project": "some-project" },
  "trustedWorkspaces": ["/Users/me/work/repo"],
  "enableTelemetry": true
}
EOF

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET   $HOME/.gemini/antigravity-cli/settings.json <- agy-settings.overrides.json"* ]]

  local settings="$HOME/.gemini/antigravity-cli/settings.json"
  # Overrides applied
  [ "$(jq -r '.enableTelemetry' "$settings")" = "false" ]
  [ "$(jq -r '.showFeedbackSurvey' "$settings")" = "false" ]
  [ "$(jq -r '.showTips' "$settings")" = "false" ]
  [ "$(jq -r '.notifications' "$settings")" = "false" ]
  # Gitignore access flags applied from file-permissions.json
  [ "$(jq -r '.allowAgentAccessGitignoreFiles' "$settings")" = "false" ]
  [ "$(jq -r '.allowTabAccessGitignoreFiles' "$settings")" = "false" ]
  [ "$(jq -r '.allowCascadeAccessGitignoreFiles' "$settings")" = "false" ]
  # Deny & allow rules applied from file-permissions.json
  [ "$(jq -r '.permissions.deny | length' "$settings")" -gt 50 ]
  [ "$(jq -r '.permissions.deny[0]' "$settings")" = "command(rm -rf)" ]
  [ "$(jq -r '.permissions.allow[0]' "$settings")" = "command(ccusage)" ]
  # Pre-existing app state untouched
  [ "$(jq -r '.gcp.project' "$settings")" = "some-project" ]
  [ "$(jq -r '.trustedWorkspaces[0]' "$settings")" = "/Users/me/work/repo" ]
}

@test "install_agy_settings_skipped_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.gemini/antigravity-cli/settings.json" ]
}

@test "install_antigravity_desktop_settings_merges_grants_and_preserves_user_settings" {
  uname() { echo "Darwin"; }
  hostname() { echo "personal-macbook-pro"; }
  export -f uname hostname

  mkdir -p "$HOME/.gemini/config"
  cat > "$HOME/.gemini/config/config.json" <<'EOF'
{
  "userSettings": {
    "autoExecutionPolicy": "CASCADE_COMMANDS_AUTO_EXECUTION_PROCEED_IN_SANDBOX",
    "themeMode": "THEME_MODE_INHERIT",
    "remoteControlHostname": "my-host"
  }
}
EOF

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SET   $HOME/.gemini/config/config.json <- file-permissions.json (globalPermissionGrants)"* ]]

  local config="$HOME/.gemini/config/config.json"
  # Existing userSettings preserved
  [ "$(jq -r '.userSettings.autoExecutionPolicy' "$config")" = "CASCADE_COMMANDS_AUTO_EXECUTION_PROCEED_IN_SANDBOX" ]
  [ "$(jq -r '.userSettings.themeMode' "$config")" = "THEME_MODE_INHERIT" ]
  [ "$(jq -r '.userSettings.remoteControlHostname' "$config")" = "my-host" ]
  # Global permission grants applied
  [ "$(jq -r '.userSettings.globalPermissionGrants.deny | length' "$config")" -gt 50 ]
  [ "$(jq -r '.userSettings.globalPermissionGrants.deny[0]' "$config")" = "command(rm -rf)" ]
  [ "$(jq -r '.userSettings.globalPermissionGrants.allow[0]' "$config")" = "command(ccusage)" ]
}

@test "install_antigravity_desktop_settings_skipped_on_linux" {
  uname() { echo "Linux"; }
  export -f uname

  run bash "$INSTALL_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.gemini/config/config.json" ]
}

@test "permissions_parity_between_claude_and_antigravity" {
  local dotfiles
  dotfiles="$(cd "$(dirname "$INSTALL_SCRIPT")" && pwd)"
  local manifest="$dotfiles/file-permissions.json"
  [ -f "$manifest" ]

  local num_files num_cmds
  num_files="$(jq '.deny.files | length' "$manifest")"
  num_cmds="$(jq '.deny.commands | length' "$manifest")"

  # Claude output check
  local claude_json
  claude_json="$(jq --arg target claude -f "$dotfiles/gen-permissions.jq" --argjson perms "$(<"$manifest")" -n)"
  local claude_deny_len
  claude_deny_len="$(echo "$claude_json" | jq '.permissions.deny | length')"

  # Antigravity CLI output check
  local agy_json
  agy_json="$(jq --arg target agy_cli -f "$dotfiles/gen-permissions.jq" --argjson perms "$(<"$manifest")" -n)"
  local agy_deny_len
  agy_deny_len="$(echo "$agy_json" | jq '.permissions.deny | length')"

  # Antigravity Desktop output check
  local desktop_json
  desktop_json="$(jq --arg target antigravity_desktop -f "$dotfiles/gen-permissions.jq" --argjson perms "$(<"$manifest")" -n)"
  local desktop_deny_len
  desktop_deny_len="$(echo "$desktop_json" | jq '.userSettings.globalPermissionGrants.deny | length')"

  # Antigravity CLI and Desktop deny rules must match exactly (files + commands)
  [ "$agy_deny_len" -eq "$((num_files + num_cmds))" ]
  [ "$desktop_deny_len" -eq "$((num_files + num_cmds))" ]

  # Claude deny includes files + commands + claude_rtk
  local num_rtk
  num_rtk="$(jq '.deny.claude_rtk | length' "$manifest")"
  [ "$claude_deny_len" -eq "$((num_files + num_cmds + num_rtk))" ]

  # Parity on allow commands
  [ "$(echo "$claude_json" | jq -r '.permissions.allow[0]')" = "Bash(ccusage)" ]
  [ "$(echo "$agy_json" | jq -r '.permissions.allow[0]')" = "command(ccusage)" ]
  [ "$(echo "$desktop_json" | jq -r '.userSettings.globalPermissionGrants.allow[0]')" = "command(ccusage)" ]
}

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
