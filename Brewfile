# Homebrew Bundle — install with: brew bundle install

# Taps
tap "hashicorp/tap"

# Formulae (CLI tools)
brew "gh"
brew "ripgrep"
brew "tesseract"
brew "fzf"
brew "zoxide"
brew "p7zip"
brew "ffmpeg"
brew "hashicorp/tap/terraform"
# Supply-chain scanner for the work-laptop skill-scan guard
# (.claude/hooks/skill-scan-guard.sh). Offline binary, no token.
brew "trivy"
# 8.4 LTS, not latest: 9.x clients drop mysql_native_password, which
# sophia-prod still uses for password auth. Keg-only, so force-link.
brew "mysql@8.4", link: true
brew "rtk"

# Casks (GUI apps / pre-built binaries)
cask "antigravity-cli"
cask "claude-code"
cask "gcloud-cli"
