#!/usr/bin/env bash
# Compare installed Claude plugin SHAs against their source repos.
# Exits 1 if any plugins have updates available (useful in CI).
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$DOTFILES/installed_plugins.json"

# Marketplace key → GitHub repo
MARKETPLACES='{
  "claude-plugins-official": "anthropics/claude-plugins-official",
  "huggingface-skills":       "huggingface/skills",
  "anthropic-agent-skills":   "anthropics/skills",
  "zimalabs":                 "zimalabs/code-decisions"
}'

# Plugins sourced from their own repos (not a subdir of the marketplace repo)
EXTERNALS='{
  "chrome-devtools-mcp": "ChromeDevTools/chrome-devtools-mcp"
}'

outdated=0

while IFS= read -r line; do
  plugin_key=$(printf '%s' "$line" | jq -r '.key')
  installed_sha=$(printf '%s' "$line" | jq -r '.sha')
  plugin_name="${plugin_key%%@*}"
  marketplace="${plugin_key##*@}"

  if [ "$installed_sha" = "null" ] || [ -z "$installed_sha" ]; then
    printf "SKIP  %s (no SHA recorded)\n" "$plugin_key"
    continue
  fi

  ext_repo=$(printf '%s' "$EXTERNALS" | jq -r --arg n "$plugin_name" '.[$n] // empty')

  if [ -n "$ext_repo" ]; then
    latest=$(gh api "repos/$ext_repo/commits?per_page=1" --jq '.[0].sha' 2>/dev/null || true)
  else
    mkt_repo=$(printf '%s' "$MARKETPLACES" | jq -r --arg m "$marketplace" '.[$m] // empty')
    if [ -z "$mkt_repo" ]; then
      printf "SKIP  %s (unknown marketplace)\n" "$plugin_key"
      continue
    fi
    latest=$(gh api "repos/$mkt_repo/commits?path=plugins/$plugin_name&per_page=1" --jq '.[0].sha' 2>/dev/null || true)
  fi

  if [ -z "$latest" ]; then
    printf "WARN  %s (could not fetch latest SHA)\n" "$plugin_key"
    continue
  fi

  if [ "$latest" = "$installed_sha" ]; then
    printf "OK    %-50s %s\n" "$plugin_key" "${installed_sha:0:8}"
  else
    printf "OUT   %-50s installed=%-8s latest=%s\n" "$plugin_key" "${installed_sha:0:8}" "${latest:0:8}"
    outdated=$((outdated + 1))
  fi
done < <(jq -c '.plugins | to_entries[] | {key: .key, sha: (.value[0].gitCommitSha // null)}' "$LOCK")

echo ""
if [ "$outdated" -gt 0 ]; then
  echo "$outdated plugin(s) have updates available. Update installed_plugins.json and re-run install.sh."
  exit 1
else
  echo "All plugins up to date."
fi
