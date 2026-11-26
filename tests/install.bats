#!/usr/bin/env bats
# Tests for install.sh bootstrap script
#
# install.sh is primarily a macOS/zsh setup. On Linux (e.g. the bwrap sandbox
# used by remote/orchestrated sessions) it skips the multi-profile machinery
# (no zsh wrapper there to reach a second/third profile) but still installs
# ~/.zshrc plus the Claude Code default profile: settings.json, hooks, skills,
# commands. CI runs on Linux, so the default (unmocked) case exercises that
# scoped path. The macOS tests below mock `uname` to Darwin to cover the
# full install path (all profiles + zsh wrapper).

setup_file() {
  export DOTFILES_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export INSTALL_SCRIPT="$DOTFILES_ROOT/install.sh"
  export CURRENT_USER="$(id -un)"
  export SHARED_FIXTURES_DIR="$(mktemp -d)"

  # Shared read-only fixtures run once per file in parallel so tests that
  # inspect install.sh outcomes don't repeat slow serial installs.
  export EMPTY_HOME="$SHARED_FIXTURES_DIR/empty"
  export LINUX_HOME="$SHARED_FIXTURES_DIR/linux"
  export LINUX_EXISTING_HOME="$SHARED_FIXTURES_DIR/linux-existing"
  export LINUX_IDEMPOTENT_HOME="$SHARED_FIXTURES_DIR/linux-idempotent"
  export DARWIN_PERSONAL_HOME="$SHARED_FIXTURES_DIR/darwin-personal"
  export DARWIN_PERSONAL_ALT_HOME="$SHARED_FIXTURES_DIR/darwin-personal-alt"
  export DARWIN_WORK_BASE_HOME="$SHARED_FIXTURES_DIR/darwin-work-base"
  export DARWIN_WORK_FULL_HOME="$SHARED_FIXTURES_DIR/darwin-work-full"
  export DARWIN_OFFICE_HOME="$SHARED_FIXTURES_DIR/darwin-office"

  mkdir -p \
    "$EMPTY_HOME" \
    "$LINUX_HOME/.grok" \
    "$LINUX_EXISTING_HOME" \
    "$LINUX_IDEMPOTENT_HOME" \
    "$DARWIN_PERSONAL_HOME/.gemini/antigravity-cli" \
    "$DARWIN_PERSONAL_HOME/.gemini/config" \
    "$DARWIN_PERSONAL_ALT_HOME/.grok" \
    "$DARWIN_WORK_BASE_HOME/.config/prodwatch" \
    "$DARWIN_WORK_FULL_HOME/work/notes/NUS-Enterprise/tools" \
    "$DARWIN_WORK_FULL_HOME/.grok" \
    "$DARWIN_OFFICE_HOME"

  # Common isolated test env for shared fixture runs
  local base_env=(
    DOTFILES_ENV=/dev/null
    DOTFILES_SKIP_NODE_TOOLS=1
    DOTFILES_SKIP_GCLOUD_PYTHON=1
    DOTFILES_SKIP_FLI=1
    DOTFILES_SKIP_ZSH_PLUGINS=1
    DOTFILES_SKIP_FINDER_DEFAULTS=1
    DOTFILES_OFFICE_USERS=no-such-office-user
  )

  # 1. Clean Linux personal install (with .grok present and Finder defaults enabled to verify both are skipped)
  (
    export HOME="$LINUX_HOME" "${base_env[@]}"
    unset DOTFILES_SKIP_FINDER_DEFAULTS
    uname() { echo "Linux"; }
    hostname() { echo "personal-linux-box"; }
    defaults() { echo "defaults $*" >> "$HOME/calls.log"; }
    killall() { echo "killall $*" >> "$HOME/calls.log"; }
    export -f uname hostname defaults killall
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/linux.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/linux.status"
  ) </dev/null &

  # 2. Linux install with pre-existing .zshrc and .zshenv
  (
    export HOME="$LINUX_EXISTING_HOME" "${base_env[@]}"
    echo "# my zshrc" > "$HOME/.zshrc"
    echo "export ZDOTDIR=/custom" > "$HOME/.zshenv"
    uname() { echo "Linux"; }
    export -f uname
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/linux-existing.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/linux-existing.status"
  ) </dev/null &

  # 3. Linux idempotent re-install (runs install.sh twice)
  (
    export HOME="$LINUX_IDEMPOTENT_HOME" "${base_env[@]}"
    uname() { echo "Linux"; }
    export -f uname
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/linux-idempotent-1.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/linux-idempotent-1.status"
    [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ] && echo "ok" >"$SHARED_FIXTURES_DIR/linux-idempotent-1.zshrc_ok"
    cp "$HOME/.zshrc" "$SHARED_FIXTURES_DIR/linux-idempotent-1.zshrc"
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/linux-idempotent-2.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/linux-idempotent-2.status"
  ) </dev/null &

  # 4. Darwin personal install (pre-existing agy & desktop app state, ANTHROPIC_AUTH_TOKEN, Finder defaults write)
  (
    export HOME="$DARWIN_PERSONAL_HOME" "${base_env[@]}" ANTHROPIC_AUTH_TOKEN="main-token"
    unset DOTFILES_SKIP_FINDER_DEFAULTS
    cat > "$HOME/.gemini/antigravity-cli/settings.json" <<'EOF'
{
  "gcp": { "project": "some-project" },
  "trustedWorkspaces": ["/Users/me/work/repo"],
  "enableTelemetry": true
}
EOF
    cat > "$HOME/.gemini/config/config.json" <<'EOF'
{
  "userSettings": {
    "autoExecutionPolicy": "CASCADE_COMMANDS_AUTO_EXECUTION_PROCEED_IN_SANDBOX",
    "themeMode": "THEME_MODE_INHERIT",
    "remoteControlHostname": "my-host"
  }
}
EOF
    uname() { echo "Darwin"; }
    hostname() { echo "personal-macbook-pro"; }
    defaults() { echo "defaults $*" >> "$HOME/calls.log"; [ "$1" != "read" ]; }
    killall() { echo "killall $*" >> "$HOME/calls.log"; }
    export -f uname hostname defaults killall
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/darwin-personal.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/darwin-personal.status"
  ) </dev/null &

  # 5. Darwin personal alt install (Finder defaults already set + ~/.grok present)
  (
    export HOME="$DARWIN_PERSONAL_ALT_HOME" "${base_env[@]}"
    unset DOTFILES_SKIP_FINDER_DEFAULTS
    uname() { echo "Darwin"; }
    hostname() { echo "personal-macbook-pro"; }
    defaults() {
      echo "defaults $*" >> "$HOME/calls.log"
      case "$3" in
        FXPreferred*) echo "Nlsv" ;;
        DSDontWrite*) echo "1" ;;
      esac
    }
    killall() { echo "killall $*" >> "$HOME/calls.log"; }
    export -f uname hostname defaults killall
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/darwin-personal-alt.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/darwin-personal-alt.status"
  ) </dev/null &

  # 6. Darwin work install without vault tool (stale prodwatch identity, non-real HOME)
  (
    export HOME="$DARWIN_WORK_BASE_HOME" "${base_env[@]}" DOTFILES_WORK_HOSTNAME="custom-corp-laptop"
    echo "PRODWATCH_GITHUB_USER=stale" > "$HOME/.config/prodwatch/identity"
    uname() { echo "Darwin"; }
    hostname() { echo "custom-corp-laptop"; }
    launchctl() { return 0; }
    trivy() { return 0; }
    defaults() { echo "defaults $*" >> "$HOME/calls.log"; [ "$1" != "read" ]; }
    dscl() { echo "NFSHomeDirectory: /Users/someone-else"; }
    export -f uname hostname launchctl trivy defaults dscl
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/darwin-work-base.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/darwin-work-base.status"
  ) </dev/null &

  # 7. Darwin work install with vault tool + .grok + real HOME
  (
    export HOME="$DARWIN_WORK_FULL_HOME" "${base_env[@]}" DOTFILES_WORK_HOSTNAME="custom-corp-laptop"
    touch "$HOME/work/notes/NUS-Enterprise/tools/new-week.sh"
    uname() { echo "Darwin"; }
    hostname() { echo "custom-corp-laptop"; }
    launchctl() { return 0; }
    trivy() { return 0; }
    defaults() { echo "defaults $*" >> "$HOME/calls.log"; [ "$1" != "read" ]; }
    dscl() { echo "NFSHomeDirectory: $HOME"; }
    export -f uname hostname launchctl trivy defaults dscl
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/darwin-work-full.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/darwin-work-full.status"
  ) </dev/null &

  # 8. Darwin office install
  (
    export HOME="$DARWIN_OFFICE_HOME" "${base_env[@]}" DOTFILES_OFFICE_USERS="$CURRENT_USER"
    uname() { echo "Darwin"; }
    hostname() { echo "office-mac-mini"; }
    launchctl() { return 0; }
    export -f uname hostname launchctl
    bash "$INSTALL_SCRIPT" >"$SHARED_FIXTURES_DIR/darwin-office.out" 2>&1
    echo $? >"$SHARED_FIXTURES_DIR/darwin-office.status"
  ) </dev/null &

  wait
}

teardown_file() {
  rm -rf "$SHARED_FIXTURES_DIR"
}

setup() {
  export HOME="$EMPTY_HOME"
  export DOTFILES_ENV=/dev/null
  export DOTFILES_SKIP_NODE_TOOLS=1
  export DOTFILES_SKIP_GCLOUD_PYTHON=1
  export DOTFILES_SKIP_FLI=1
  export DOTFILES_SKIP_ZSH_PLUGINS=1
  export DOTFILES_SKIP_FINDER_DEFAULTS=1
  export DOTFILES_OFFICE_USERS="no-such-office-user"
}

# --- Linux: scoped install (default profile only, no zsh/ZDOTDIR) ---

@test "install_completes_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]
  local out
  out="$(<"$SHARED_FIXTURES_DIR/linux.out")"
  [[ "$out" == *"GEN   $LINUX_HOME/.claude/settings.json (default)"* ]]
  [[ "$out" == *"Done."* ]]
}

@test "install_writes_only_default_profile_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]

  # ~/.zshrc IS installed on Linux (as a real file, not a symlink — see
  # setup_zsh_config_writes_real_zshrc_file_on_linux for why), but the
  # multi-profile wrapper stays macOS-only (no zsh `cl` dispatcher to reach it)
  [ ! -e "$LINUX_HOME/.zshenv" ]
  [ -e "$LINUX_HOME/.zshrc" ]
  [ ! -L "$LINUX_HOME/.zshrc" ]
  [ ! -e "$LINUX_HOME/.claude-profiles.zsh" ]

  # Default Claude profile IS installed
  [ -e "$LINUX_HOME/.claude/settings.json" ]
  [ -d "$LINUX_HOME/.claude/skills" ]
  [ -d "$LINUX_HOME/.claude/hooks" ]
  [ -L "$LINUX_HOME/.claude/hooks/db-guard.sh" ]

  # ...but not the macOS-only extras: other profiles, plugin lock
  [ ! -d "$LINUX_HOME/.claude-second-profile" ]
  [ ! -d "$LINUX_HOME/.claude-third-profile" ]
  [ ! -e "$LINUX_HOME/.claude/plugins/installed_plugins.json" ]
}

@test "install_default_profile_settings_on_linux_has_hooks_and_sonnet" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]

  # Personal (non-work) machine: model forced to sonnet regardless of OS;
  # 4-hook Bash PreToolUse chain + mysql rate limiter + symlink-memory PostToolUse present;
  # deepseek-only UserPromptSubmit guard must NOT be wired into the default profile.
  jq -e '
    .model == "sonnet"
    and ([.hooks.PreToolUse[].hooks[].command] | length) == 5
    and .hooks.PostToolUse[0].hooks[0].command == "bash ~/.claude/hooks/symlink-memory.sh"
    and (.hooks | has("UserPromptSubmit") | not)
  ' "$LINUX_HOME/.claude/settings.json" >/dev/null
}

@test "install_leaves_existing_home_files_untouched_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux-existing.status")" -eq 0 ]

  # Pre-existing user files must survive an install attempt on Linux
  grep -q "# my zshrc" "$LINUX_EXISTING_HOME/.zshrc"
  [ ! -L "$LINUX_EXISTING_HOME/.zshrc" ]
  grep -q "export ZDOTDIR=/custom" "$LINUX_EXISTING_HOME/.zshenv"
  [ ! -L "$LINUX_EXISTING_HOME/.zshenv" ]
}

@test "setup_zsh_config_writes_real_zshrc_file_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux-idempotent-1.status")" -eq 0 ]

  # A real file, NOT a symlink: bwrap (the sandbox this path targets) follows
  # symlinks when precomputing tmpfs bind-mount points, so a symlink whose
  # target isn't already in that list fails with ENOENT. A real file with a
  # source line only needs bwrap to resolve two concrete paths.
  [ -f "$SHARED_FIXTURES_DIR/linux-idempotent-1.zshrc_ok" ]
  grep -qF "source \"$DOTFILES_ROOT/.zshrc\"" "$SHARED_FIXTURES_DIR/linux-idempotent-1.zshrc"

  # Re-running install.sh regenerates the same source-file, rather than
  # getting skipped as a foreign file (idempotent re-install)
  [ "$(<"$SHARED_FIXTURES_DIR/linux-idempotent-2.status")" -eq 0 ]
  [ ! -L "$LINUX_IDEMPOTENT_HOME/.zshrc" ]
  grep -qF "source \"$DOTFILES_ROOT/.zshrc\"" "$LINUX_IDEMPOTENT_HOME/.zshrc"
}

# --- macOS: real install path (uname mocked to Darwin) ---

@test "weekly_cutover_agent_skipped_on_non_work_machine" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.out")" == *"SKIP  weekly-cutover agent (non-work machine)"* ]]
  # No plist may be generated for any label on a non-work machine
  [ ! -e "$DARWIN_PERSONAL_HOME/Library/LaunchAgents/com.$CURRENT_USER.weekly-cutover.plist" ]
}

@test "weekly_cutover_agent_installed_on_work_machine_with_vault_tool" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-full.status")" -eq 0 ]

  local plist="$DARWIN_WORK_FULL_HOME/Library/LaunchAgents/com.$CURRENT_USER.weekly-cutover.plist"
  [ -f "$plist" ]
  grep -q "new-week.sh" "$plist"
  grep -q "<string>--next</string>" "$plist"
  # Wednesday 14:00 schedule
  grep -q "<key>Weekday</key><integer>3</integer><key>Hour</key><integer>14</integer>" "$plist"
}

@test "weekly_cutover_agent_skipped_on_work_machine_without_vault_tool" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-base.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-work-base.out")" == *"SKIP  weekly-cutover agent (no "* ]]
  [ ! -e "$DARWIN_WORK_BASE_HOME/Library/LaunchAgents/com.$CURRENT_USER.weekly-cutover.plist" ]
}

@test "install_agy_settings_merges_overrides_and_preserves_app_state" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.out")" == *"SET   $DARWIN_PERSONAL_HOME/.gemini/antigravity-cli/settings.json <- agy-settings.overrides.json"* ]]

  local settings="$DARWIN_PERSONAL_HOME/.gemini/antigravity-cli/settings.json"
  # Overrides applied, gitignore flags + deny/allow rules applied, pre-existing app state untouched
  jq -e --arg home "$DARWIN_PERSONAL_HOME" '
    .agentMode == "auto"
    and .enableTerminalSandbox == true
    and .model == "Gemini 4 Neon (Medium)"
    and .enableTelemetry == false
    and .showFeedbackSurvey == false
    and .showTips == false
    and .notifications == false
    and .allowAgentAccessGitignoreFiles == false
    and .allowTabAccessGitignoreFiles == false
    and .allowCascadeAccessGitignoreFiles == false
    and (.permissions.deny | length) > 20
    and .permissions.deny[0] == "command(rm -rf)"
    and (.permissions.deny | index("read_file(\($home)/.ssh)")) != null
    and (.permissions.deny | index("read_file(\($home)/.aws)")) != null
    and (.permissions.deny | index("read_file(\($home)/.config/gcloud)")) != null
    and (.permissions.deny | index("read_file(\($home)/.zsh_history)")) != null
    and (.permissions.deny | index("read_file(\($home)/.env)")) != null
    and .permissions.allow[0] == "command(ccusage)"
    and (.permissions.allow | index("read_file(/tmp/ts-pending.json)")) != null
    and (.permissions.allow | index("write_file(/private/tmp/ts-decisions.json)")) != null
    and .gcp.project == "some-project"
    and .trustedWorkspaces[0] == "/Users/me/work/repo"
  ' "$settings" >/dev/null
}

@test "install_agy_settings_skipped_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]
  [ ! -e "$LINUX_HOME/.gemini/antigravity-cli/settings.json" ]
}

@test "install_antigravity_desktop_settings_merges_grants_and_preserves_user_settings" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.out")" == *"SET   $DARWIN_PERSONAL_HOME/.gemini/config/config.json <- file-permissions.json (globalPermissionGrants)"* ]]

  local config="$DARWIN_PERSONAL_HOME/.gemini/config/config.json"
  # Existing userSettings preserved + global permission grants applied
  jq -e --arg home "$DARWIN_PERSONAL_HOME" '
    .userSettings.autoExecutionPolicy == "CASCADE_COMMANDS_AUTO_EXECUTION_PROCEED_IN_SANDBOX"
    and .userSettings.themeMode == "THEME_MODE_INHERIT"
    and .userSettings.remoteControlHostname == "my-host"
    and (.userSettings.globalPermissionGrants.deny | length) > 20
    and .userSettings.globalPermissionGrants.deny[0] == "command(rm -rf)"
    and (.userSettings.globalPermissionGrants.deny | index("read_file(\($home)/.ssh)")) != null
    and .userSettings.globalPermissionGrants.allow[0] == "command(ccusage)"
    and (.userSettings.globalPermissionGrants.allow | index("write_file(/tmp/ts-decisions.json)")) != null
  ' "$config" >/dev/null
}

@test "install_antigravity_desktop_settings_skipped_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]
  [ ! -e "$LINUX_HOME/.gemini/config/config.json" ]
}

@test "permissions_parity_between_claude_and_antigravity" {
  local manifest="$DOTFILES_ROOT/file-permissions.json"
  [ -f "$manifest" ]

  local perms claude_json agy_json desktop_json
  perms="$(<"$manifest")"
  claude_json="$(jq --arg target claude -f "$DOTFILES_ROOT/gen-permissions.jq" --argjson perms "$perms" -n)"
  agy_json="$(jq --arg home "$HOME" --arg target agy_cli -f "$DOTFILES_ROOT/gen-permissions.jq" --argjson perms "$perms" -n)"
  desktop_json="$(jq --arg home "$HOME" --arg target antigravity_desktop -f "$DOTFILES_ROOT/gen-permissions.jq" --argjson perms "$perms" -n)"

  jq -ne \
    --argjson manifest "$perms" \
    --argjson claude "$claude_json" \
    --argjson agy "$agy_json" \
    --argjson desktop "$desktop_json" '
    # Claude output retains all relative/glob rules and omits agy-only files
    ($claude.permissions.deny | length) == (($manifest.deny.files | length) + ($manifest.deny.commands | length))
    and ($claude.permissions.deny | map(select(. == "Read(~/.ssh)" or . == "Read(~/.env)")) | length) == 0
    # Antigravity CLI and Desktop deny rules match each other and contain >20 rules
    and ($agy.permissions.deny | length) > 20
    and $agy.permissions.deny == $desktop.userSettings.globalPermissionGrants.deny
    # Sandbox safety invariant: every read_file(...) / write_file(...) target is absolute and glob-free
    and ([($agy.permissions.deny[]), ($agy.permissions.allow[])
          | capture("^(?:read|write)_file\\((?<p>.*)\\)$").p
          | select((startswith("/") | not) or test("[*?\\[]"))] | length) == 0
    # Parity on allow commands
    and $claude.permissions.allow[0] == "Bash(ccusage)"
    and $agy.permissions.allow[0] == "command(ccusage)"
    and $desktop.userSettings.globalPermissionGrants.allow[0] == "command(ccusage)"
    and $agy.permissions.allow == $desktop.userSettings.globalPermissionGrants.allow
    and ($claude.permissions.allow | map(select(test("ts-"))) | length) == 0
  ' >/dev/null
}

@test "setup_zsh_config_symlinks_zshrc_on_macos" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  # On macOS, ~/.zshrc is a symlink into the dotfiles repo
  [ -L "$DARWIN_PERSONAL_HOME/.zshrc" ]
  [ "$(readlink "$DARWIN_PERSONAL_HOME/.zshrc")" = "$DOTFILES_ROOT/.zshrc" ]
  # No .zshenv is ever created (Linux ZDOTDIR path was removed)
  [ ! -e "$DARWIN_PERSONAL_HOME/.zshenv" ]
}

# --is-work-machine is the single source of truth the Brewfile shells out to
# (via `system`) instead of duplicating the hostname default.
@test "is_work_machine_flag_exits_1_off_work_machine" {
  hostname() { echo "personal-macbook-pro"; }
  export -f hostname

  run bash "$INSTALL_SCRIPT" --is-work-machine
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "is_work_machine_flag_exits_0_on_work_machine" {
  hostname() { echo "custom-corp-laptop"; }
  export -f hostname
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"

  run bash "$INSTALL_SCRIPT" --is-work-machine
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ghostty_config_linked_on_any_mac" {
  [ -L "$DARWIN_PERSONAL_HOME/.config/ghostty/config" ]
  [ "$(readlink "$DARWIN_PERSONAL_HOME/.config/ghostty/config")" = "$DOTFILES_ROOT/ghostty/config" ]
}

@test "ghostty_config_linked_on_work_mac" {
  [ -L "$DARWIN_WORK_BASE_HOME/.config/ghostty/config" ]
}

@test "finder_defaults_written_and_finder_restarted_on_mac" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  local log="$DARWIN_PERSONAL_HOME/calls.log"
  grep -qx "defaults write com.apple.finder FXPreferredViewStyle -string Nlsv" "$log"
  grep -qx "defaults write com.apple.finder FXPreferredSearchViewStyle -string Nlsv" "$log"
  grep -qx "defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true" "$log"
  grep -qx "defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true" "$log"
  grep -qx "killall Finder" "$log"
}

@test "finder_not_restarted_when_defaults_already_set" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal-alt.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-personal-alt.out")" == *"OK    Finder defaults already list view"* ]]
  local log="$DARWIN_PERSONAL_ALT_HOME/calls.log"
  ! grep -q "defaults write com.apple.finder" "$log"
  ! grep -q "killall Finder" "$log"
}

@test "finder_defaults_skipped_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]
  [ ! -e "$LINUX_HOME/calls.log" ]
}

@test "swiftbar_plugin_dir_not_written_when_home_is_not_real_home" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-base.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-work-base.out")" == *"SKIP  SwiftBar PluginDirectory (HOME is not the real user home)"* ]]
  ! grep -q "com.ameba.SwiftBar" "$DARWIN_WORK_BASE_HOME/calls.log" 2>/dev/null
}

@test "swiftbar_plugin_dir_written_when_home_is_real_home" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-full.status")" -eq 0 ]
  grep -qx "defaults write com.ameba.SwiftBar PluginDirectory $DARWIN_WORK_FULL_HOME/.config/swiftbar" "$DARWIN_WORK_FULL_HOME/calls.log"
}

@test "is_office_machine_flag_exits_0_for_shared_account_on_mac" {
  uname() { echo "Darwin"; }
  hostname() { echo "office-mac-mini"; }
  export -f uname hostname
  export DOTFILES_OFFICE_USERS="$CURRENT_USER"

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "is_office_machine_flag_matches_any_listed_account" {
  uname() { echo "Darwin"; }
  hostname() { echo "office-macbook"; }
  export -f uname hostname
  export DOTFILES_OFFICE_USERS="other-office-account $CURRENT_USER"

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 0 ]
}

@test "is_office_machine_flag_rejects_account_name_prefix" {
  uname() { echo "Darwin"; }
  hostname() { echo "office-macbook"; }
  export -f uname hostname
  export DOTFILES_OFFICE_USERS="${CURRENT_USER}x"

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 1 ]
}

@test "is_office_machine_flag_exits_1_for_other_accounts" {
  uname() { echo "Darwin"; }
  hostname() { echo "office-mac-mini"; }
  export -f uname hostname

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 1 ]
}

@test "is_office_machine_flag_exits_1_on_linux" {
  uname() { echo "Linux"; }
  export -f uname
  export DOTFILES_OFFICE_USERS="$CURRENT_USER"

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 1 ]
}

@test "work_machine_is_never_an_office_machine" {
  uname() { echo "Darwin"; }
  hostname() { echo "custom-corp-laptop"; }
  export -f uname hostname
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"
  export DOTFILES_OFFICE_USERS="$CURRENT_USER"

  run bash "$INSTALL_SCRIPT" --is-office-machine
  [ "$status" -eq 1 ]
}

@test "office_machine_keeps_manifest_model_and_gets_swiftbar_and_grok_guard" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-office.status")" -eq 0 ]
  local out
  out="$(<"$SHARED_FIXTURES_DIR/darwin-office.out")"
  [[ "$out" == *"SKIP  sonnet switch (work/office machine"* ]]
  [ "$(jq -r '.model' "$DARWIN_OFFICE_HOME/.claude/settings.json")" != "sonnet" ]
  [ -L "$DARWIN_OFFICE_HOME/.config/swiftbar/prodwatch.60s.sh" ]
  grep -qx "PRODWATCH_GITHUB_USER=NUSXGrok" "$DARWIN_OFFICE_HOME/.config/prodwatch/identity"
  grep -qx "PRODWATCH_WORK_AUTHOR=NUSXGrok" "$DARWIN_OFFICE_HOME/.config/prodwatch/identity"
  [ -x "$DARWIN_OFFICE_HOME/.grok/hooks/identity-guard.sh" ]
  [ ! -L "$DARWIN_OFFICE_HOME/.grok/hooks/identity-guard.sh" ]
  jq -e --arg users "$CURRENT_USER" '.hooks.PreToolUse[0].hooks[0].command == "GROK_GUARD_OFFICE_USERS='"'"'\($users)'"'"' bash ~/.grok/hooks/identity-guard.sh"' "$DARWIN_OFFICE_HOME/.grok/hooks/identity-guard.json"
  [[ "$out" == *"SKIP  daily-session-log agent (non-work machine)"* ]]
  [[ "$out" == *"SKIP  trivy DB pre-warm (non-work machine)"* ]]
}

@test "grok_guard_skipped_on_personal_mac" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]
  [[ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.out")" == *"SKIP  grok identity guard (non-office machine without Grok)"* ]]
  [ ! -e "$DARWIN_PERSONAL_HOME/.grok/hooks/identity-guard.sh" ]
}

@test "grok_guard_installed_on_personal_mac_with_grok" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal-alt.status")" -eq 0 ]
  [ -x "$DARWIN_PERSONAL_ALT_HOME/.grok/hooks/identity-guard.sh" ]
  jq -e '.hooks.PreToolUse[0].hooks[0].command == "GROK_GUARD_OFFICE_USERS='"'"'no-such-office-user'"'"' bash ~/.grok/hooks/identity-guard.sh"' "$DARWIN_PERSONAL_ALT_HOME/.grok/hooks/identity-guard.json"
}

@test "grok_guard_installed_on_work_mac_with_grok" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-full.status")" -eq 0 ]
  [ -x "$DARWIN_WORK_FULL_HOME/.grok/hooks/identity-guard.sh" ]
}

@test "grok_guard_not_installed_on_linux" {
  [ "$(<"$SHARED_FIXTURES_DIR/linux.status")" -eq 0 ]
  [ ! -e "$LINUX_HOME/.grok/hooks/identity-guard.sh" ]
}

@test "work_machine_has_no_prodwatch_identity_override" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-work-base.status")" -eq 0 ]
  [ ! -e "$DARWIN_WORK_BASE_HOME/.config/prodwatch/identity" ]
}

@test "alt_profile_inherits_default_but_isolates_memory_on_macos" {
  [ "$(<"$SHARED_FIXTURES_DIR/darwin-personal.status")" -eq 0 ]

  local alt="$DARWIN_PERSONAL_HOME/.claude-alt-profile"
  [ -f "$alt/settings.json" ]
  jq -e --slurpfile def "$DARWIN_PERSONAL_HOME/.claude/settings.json" '
    .hooks.PreToolUse == $def[0].hooks.PreToolUse
    and .model == "sonnet"
    and (.env.ANTHROPIC_AUTH_TOKEN // "unset") == "unset"
    and (.hooks.PostToolUse | length) == 0
  ' "$alt/settings.json" >/dev/null

  [ -L "$alt/skills" ]
  [ "$(readlink "$alt/skills")" = "$DARWIN_PERSONAL_HOME/.claude/skills" ]
  [ ! -e "$alt/projects" ]

  grep -q 'a-claude() { claude_with_profile "$HOME/.claude-alt-profile"' "$DARWIN_PERSONAL_HOME/.claude-profiles.zsh"
}
