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

setup_profile() {
  local profile="$1"
  local env_var="$2"
  mkdir -p "$HOME/$profile"
  symlink "$profile/CLAUDE.md"
  jq --arg token "${!env_var:-}" \
    '.env.ANTHROPIC_AUTH_TOKEN = $token' \
    "$DOTFILES/$profile/settings.json" \
    > "$HOME/$profile/settings.json"
  echo "GEN   $HOME/$profile/settings.json"
}

# Symlinks
symlink .zshrc
symlink .env.example

# Profiles: (profile_dir, env_var_name)
setup_profile ".claude-second-profile" "Z_AI_AUTH_TOKEN"
setup_profile ".claude-third-profile" "DASHSCOPE_AUTH_TOKEN"

git -C "$DOTFILES" config core.hooksPath .githooks
echo "HOOK  core.hooksPath -> .githooks"

echo "Done."
