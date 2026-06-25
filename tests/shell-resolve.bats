#!/usr/bin/env bats
# Integration test: source the real .zshrc end-to-end and assert that the two
# command resolutions we care about actually work:
#   - `z`             — provided by `zoxide init zsh` (.zshrc)
#   - `claude`/`claude version` — provided by the generated ~/.claude-profiles.zsh wrapper
#
# Both are guarded behind `command -v`, so we stub fake `zoxide`/`claude`
# binaries on PATH and a no-op oh-my-zsh, then run a real zsh that sources the
# unmodified repo .zshrc.
#
# Note on PATH: .zshrc re-prepends /opt/homebrew/bin and ~/.local/bin, so a real
# zoxide/claude already installed (e.g. on the dev machine) can shadow the stubs.
# Resolution (`whence -w`) is unaffected — that's the core assertion. For the
# claude forwarding test we re-prepend the stub dir after sourcing; the wrapper
# resolves `command claude` at call time, so the stub then wins regardless.

setup() {
  command -v zsh >/dev/null || skip "zsh not installed"

  DOTFILES="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INSTALL_SCRIPT="$DOTFILES/install.sh"

  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Isolate from the repo's real .env (install.sh sources it before the
  # sourced-mode guard, so this still applies even though no install runs).
  export DOTFILES_ENV=/dev/null

  # .zshrc hardcodes ZSH="$HOME/.oh-my-zsh" and sources $ZSH/oh-my-zsh.sh.
  # Provide a no-op so the file sources cleanly without a real Oh My Zsh.
  mkdir -p "$HOME/.oh-my-zsh"
  : > "$HOME/.oh-my-zsh/oh-my-zsh.sh"

  # Stub binaries the .zshrc guards on with `command -v`.
  STUB_BIN="$HOME/stub-bin"
  mkdir -p "$STUB_BIN"

  # Fake zoxide: `zoxide init zsh` must emit a `z` function, mirroring real zoxide.
  cat > "$STUB_BIN/zoxide" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "init" ]; then
  echo 'z() { echo "zoxide jumped: $*"; }'
fi
EOF
  chmod +x "$STUB_BIN/zoxide"

  # Fake claude: echo the profile dir and args so we can assert the wrapper
  # set CLAUDE_CONFIG_DIR and forwarded `version`.
  cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude-stub args=$* CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
EOF
  chmod +x "$STUB_BIN/claude"

  export PATH="$STUB_BIN:$PATH"

  # Generate just ~/.claude-profiles.zsh from providers.json. Sourcing install.sh
  # only loads its functions (the install steps self-skip when sourced), so we
  # skip the git clones / symlinks / settings generation we don't need here.
  source "$INSTALL_SCRIPT"
  generate_zsh_profiles >/dev/null
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Run a snippet in a zsh that has first sourced the real repo .zshrc.
run_zsh() {
  run zsh -c "source '$DOTFILES/.zshrc' >/dev/null 2>&1; $1"
}

@test "z resolves to a function after sourcing .zshrc" {
  run_zsh 'whence -w z'
  [ "$status" -eq 0 ]
  [[ "$output" == *"z: function"* ]]
}

@test "claude resolves to the profile wrapper after sourcing .zshrc" {
  run_zsh 'whence -w claude'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude: function"* ]]
}

@test "claude version forwards to the binary with the default profile dir" {
  # Re-prepend the stub so `command claude` (resolved at call time inside the
  # wrapper) hits our fake binary even if a real claude is installed.
  run_zsh 'export PATH="'"$STUB_BIN"':$PATH"; claude version'
  [ "$status" -eq 0 ]
  [[ "$output" == *"args=version"* ]]
  [[ "$output" == *"CLAUDE_CONFIG_DIR=$HOME/.claude"* ]]
}
