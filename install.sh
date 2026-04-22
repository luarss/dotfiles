#!/bin/bash -eu
# Bootstrap script — symlinks dotfiles into $HOME and generates secret-bearing configs

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# Load tokens from .env if present
if [ -f "$DOTFILES/.env" ]; then
  set -a
  . "$DOTFILES/.env"
  set +a
fi

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

install_skills() {
  local skills_src="$DOTFILES/skills"
  local skills_dst="$HOME/.claude/skills"
  mkdir -p "$skills_dst"
  for skill_dir in "$skills_src"/*/; do
    local name
    name="$(basename "$skill_dir")"
    local dst="$skills_dst/$name"
    if [ -e "$dst" ]; then
      echo "SKIP  $dst (already exists)"
    else
      ln -s "$skill_dir" "$dst"
      echo "LINK  $dst -> $skill_dir"
    fi
  done
}

install_zsh_plugin() {
  local repo="$1"
  local name="${2:-$(basename "$repo" .git)}"
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local plugin_dir="$zsh_custom/plugins/$name"

  if [ -d "$plugin_dir/.git" ]; then
    echo "SKIP  $name (already installed)"
    return
  fi

  mkdir -p "$zsh_custom/plugins"
  git clone --depth=1 "https://github.com/$repo.git" "$plugin_dir" 2>/dev/null
  echo "INST  $name plugin"
}

# Symlinks
symlink .zshrc
symlink .env.example

# Profiles: (profile_dir, env_var_name)
setup_profile ".claude" "ANTHROPIC_AUTH_TOKEN"
setup_profile ".claude-second-profile" "Z_AI_AUTH_TOKEN"
setup_profile ".claude-third-profile" "DASHSCOPE_AUTH_TOKEN"

# Install skills into ~/.claude/skills (append-only)
install_skills

git -C "$DOTFILES" config core.hooksPath .githooks
echo "HOOK  core.hooksPath -> .githooks"

# Install custom zsh plugins (requires Oh My Zsh to be installed first)
install_zsh_plugin "zsh-users/zsh-autosuggestions"
install_zsh_plugin "zsh-users/zsh-syntax-highlighting"

echo "Done."
