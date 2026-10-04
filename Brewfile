# Homebrew Bundle — install with: brew bundle install

# Work-vs-personal gate — delegates to install.sh (single source of truth for
# what counts as the work machine) instead of duplicating the hostname check.
is_work_machine = system(File.expand_path("install.sh", __dir__), "--is-work-machine",
                          out: File::NULL, err: File::NULL)

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
brew "rtk"

if is_work_machine
  # Supply-chain scanner for the work-laptop skill-scan guard
  # (.claude/hooks/skill-scan-guard.sh). Offline binary, no token.
  brew "trivy"
  # 8.4 LTS, not latest: 9.x clients drop mysql_native_password, which
  # sophia-prod still uses for password auth. Keg-only, so force-link.
  brew "mysql@8.4", link: true
end

# Casks (GUI apps / pre-built binaries)
cask "antigravity-cli"
cask "claude-code"
cask "gcloud-cli"

if is_work_machine
  # Menu-bar productivity widget host (.config/swiftbar/prodwatch.60s.sh).
  # install.sh symlinks the plugin and points SwiftBar at it.
  cask "swiftbar"
else
  cask "ghostty"
  cask "font-jetbrains-mono-nerd-font"
end
