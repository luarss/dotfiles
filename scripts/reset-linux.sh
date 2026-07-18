#!/usr/bin/env bash
# Reset dotfiles artifacts left on a Linux machine by an older install.sh.
#
# install.sh now no-ops on Linux, but earlier versions generated a ZDOTDIR
# ~/.zshenv, the Claude profile dirs, and a batch of repo symlinks. This
# removes exactly those artifacts and nothing else — it never touches your
# real ~/.claude data (projects, memory, auth) or a hand-written ~/.zshenv.
#
# Usage: reset-linux.sh [-f|--force]
#   (no args)  dry run — print what would be removed, delete nothing
#   -f         actually remove the artifacts
set -eu

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(uname)" != "Linux" ]; then
  echo "This reset is Linux-only (uname is $(uname)); nothing to do."
  exit 0
fi

force=false
case "${1:-}" in
  -f|--force) force=true ;;
  "") ;;
  *) echo "Usage: reset-linux.sh [-f|--force]" >&2; exit 2 ;;
esac

profile_dirs=(
  "$HOME/.claude"
  "$HOME/.claude-second-profile"
  "$HOME/.claude-third-profile"
)

# Repo-pointing symlinks inside the profile dirs (skills, hooks, commands,
# AGENTS.md/CLAUDE.md/RTK.md, status-line.sh, models.json).
symlinks=()
for d in "${profile_dirs[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r l; do symlinks+=("$l"); done \
    < <(find "$d" -maxdepth 3 -type l -lname "$DOTFILES/*" 2>/dev/null)
done

# Generated real files that install.sh wrote into $HOME.
files=()
for f in \
  "$HOME/.claude-profiles.zsh" \
  "$HOME/.claude/settings.json" \
  "$HOME/.claude/plugins/installed_plugins.json"; do
  [ -e "$f" ] && files+=("$f")
done

# The two fully-generated profile dirs (safe to remove wholesale; the default
# ~/.claude dir is NOT in this list because it also holds real user data).
dirs=()
for d in "$HOME/.claude-second-profile" "$HOME/.claude-third-profile"; do
  [ -e "$d" ] && dirs+=("$d")
done

# The ZDOTDIR pointer — only if it actually points at this repo.
zshenv=""
if [ -f "$HOME/.zshenv" ] && grep -q "ZDOTDIR=\"$DOTFILES\"" "$HOME/.zshenv" 2>/dev/null; then
  zshenv="$HOME/.zshenv"
fi

# Report
found=false
print_group() {
  local label="$1"; shift
  [ "$#" -gt 0 ] || return 0
  found=true
  echo "$label"
  printf '  %s\n' "$@"
}
print_group "ZDOTDIR pointer (repo-owned):" ${zshenv:+"$zshenv"}
print_group "repo symlinks:" "${symlinks[@]:-}"
print_group "generated files:" "${files[@]:-}"
print_group "generated profile dirs:" "${dirs[@]:-}"

if ! $found; then
  echo "Nothing to reset — no dotfiles artifacts found."
  exit 0
fi

if ! $force; then
  echo
  echo "Dry run. Re-run with -f to remove the above."
  exit 0
fi

# Remove
[ -n "$zshenv" ] && rm -f "$zshenv" && echo "RM    $zshenv"
for l in "${symlinks[@]:-}"; do [ -n "$l" ] && rm -f "$l" && echo "RM    $l"; done
for f in "${files[@]:-}"; do [ -n "$f" ] && rm -f "$f" && echo "RM    $f"; done
for d in "${dirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d" && echo "RM    $d"; done

echo "Done."
echo
echo "Note: git core.hooksPath may still be set in this clone. To revert:"
echo "  git -C \"$DOTFILES\" config --unset core.hooksPath"
echo "Note: zsh will fall back to your own ~/.zshrc/~/.zshenv now. To keep the"
echo "repo's zsh config on Linux, add to your ~/.zshrc:  source \"$DOTFILES/.zshrc\""
