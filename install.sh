#!/bin/bash -eu
# Bootstrap script — symlinks dotfiles into $HOME and generates secret-bearing configs

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

symlink() {
  local src="$DOTFILES/$1"
  local dst="$HOME/$1"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "SKIP  $dst (exists and is not a symlink)"
    return
  fi
  ln -sf "$src" "$dst"
  echo "LINK  $dst -> $src"
}

symlink .zshrc
symlink .env.example

# --- .claude-second-profile ---
# CLAUDE.md can be symlinked (no secrets), but settings.json must be generated
# because it contains ANTHROPIC_AUTH_TOKEN.
mkdir -p "$HOME/.claude-second-profile"
symlink .claude-second-profile/CLAUDE.md

jq --arg token "${ANTHROPIC_AUTH_TOKEN:-}" \
  '.env.ANTHROPIC_AUTH_TOKEN = $token' \
  "$DOTFILES/.claude-second-profile/settings.json" \
  > "$HOME/.claude-second-profile/settings.json"
echo "GEN   $HOME/.claude-second-profile/settings.json"

echo "Done."
