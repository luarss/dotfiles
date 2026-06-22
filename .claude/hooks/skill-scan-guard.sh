#!/usr/bin/env bash
# Skill/Plugin Scan Guard — PreToolUse hook (matcher: Bash)
# Scans a Claude plugin/skill with Snyk agent-scan BEFORE it is installed,
# blocking the install when the scanner reports a problem.
#
# Wired ONLY into the default (.claude) profile via providers.json overrides
# (listed before `rtk hook claude` so it inspects the original command).
# Exit codes: 0 = allow, 2 = block.
#
# Gating — WORK LAPTOP ONLY. If `hostname -s` != $DOTFILES_WORK_HOSTNAME
# (default Shuis-MacBook-Air) the guard no-ops immediately, so personal
# machines never scan and never need SNYK_TOKEN. Same hostname switch the
# routine restore + sonnet switch in install.sh use.
#
# Scope: fires on plugin/skill INSTALL commands run through Bash:
#   - `claude plugin install <target>`
#   - `claude plugin marketplace add <target>`
# The <target> is scanned when it resolves to something fetchable:
#   - an existing local path / SKILL.md           -> scanned in place
#   - a git URL (https://….git, git@…, github:o/r) -> shallow-cloned to a
#                                                     temp dir, scanned, removed
# A bare marketplace name (nothing local to fetch yet) can't be pre-scanned, so
# the guard ALLOWS it with a reminder to scan post-install. Skills cloned by
# hand (plain `git clone` into ~/.claude/skills) are out of scope, like
# db-guard's `psql -f` blind spot.
#
# Allowlist: targets matching a trusted-marketplace glob skip the scan. The
# built-in list is the nus-etp org (all URL forms); SKILL_SCAN_ALLOWLIST
# (whitespace/newline-separated shell globs) appends ad-hoc entries.
#
# Fail-closed: when a scannable target IS present but the scanner can't run
# (default uvx scanner with no SNYK_TOKEN, or the scanner binary is missing),
# the install is BLOCKED rather than waved through unscanned.
#
# Scanner command is overridable via SKILL_SCAN_CMD (default:
# `uvx snyk-agent-scan@0.5.10 --json`) — the test suite stubs it to assert
# behaviour without a network call. The version is pinned (not @latest):
# snyk-agent-scan is a closed-source PyPI package with no public git repo, so
# the immutable reference is version + wheel sha256 (recorded in AGENTS.md),
# not a commit SHA. PyPI forbids re-uploading a version, so @0.5.10 over HTTPS
# resolves to that exact artifact; bump deliberately, never float on @latest.

set -uo pipefail

# --- Work-laptop gate -------------------------------------------------------
WORK_HOSTNAME="${DOTFILES_WORK_HOSTNAME:-Shuis-MacBook-Air}"
[[ "$(hostname -s 2>/dev/null)" == "$WORK_HOSTNAME" ]] || exit 0

# --- Parse the tool input ---------------------------------------------------
INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

# Detect a plugin/skill install command and capture the target argument.
target=""
if [[ "$COMMAND" =~ claude[[:space:]]+plugin[[:space:]]+install[[:space:]]+([^[:space:]]+) ]]; then
  target="${BASH_REMATCH[1]}"
elif [[ "$COMMAND" =~ claude[[:space:]]+plugin[[:space:]]+marketplace[[:space:]]+add[[:space:]]+([^[:space:]]+) ]]; then
  target="${BASH_REMATCH[1]}"
else
  exit 0   # not an install command — allow
fi

# Strip surrounding quotes from the captured target.
target="${target%\"}"; target="${target#\"}"
target="${target%\'}"; target="${target#\'}"

# --- Trusted-source allowlist (skip the scan) -------------------------------
# Targets matching any of these globs are treated as trusted internal
# marketplaces and skip the scan entirely. Each entry is a shell GLOB (not
# regex) matched against the raw target, so one list covers every URL form the
# guard recognizes (and local paths). The built-in list is the nus-etp org's
# marketplace; SKILL_SCAN_ALLOWLIST (whitespace/newline-separated globs) is
# appended for ad-hoc additions without editing this file.
_allow=(
  'https://github.com/nus-etp/*'
  'git@github.com:nus-etp/*'
  'github:nus-etp/*'
)
if [[ -n "${SKILL_SCAN_ALLOWLIST:-}" ]]; then
  # read -ra word-splits without filesystem glob-expansion, so patterns stay
  # literal; the unquoted RHS of [[ == ]] below is what does the glob match.
  IFS=$' \t\n' read -rd '' -a _extra <<<"$SKILL_SCAN_ALLOWLIST" || true
  _allow+=("${_extra[@]}")
fi
for pat in "${_allow[@]}"; do
  # shellcheck disable=SC2053
  if [[ "$target" == $pat ]]; then
    echo "skill-scan: '$target' matches allowlist ('$pat') — trusted internal source, skipping scan." >&2
    exit 0
  fi
done

block() { echo "BLOCKED (skill-scan): $1" >&2; echo "Command: ${COMMAND:0:200}" >&2; exit 2; }

# Decide allow/block from the scanner's --json output, NOT its exit code:
# snyk-agent-scan exits 0 even when it reports high-severity findings (and its
# --ci flag is unusable here — it demands --dangerously-run-mcp-servers and
# errors out on skills). So we run with --json and count the reported `issues`;
# any issue blocks. Unparseable/empty output (a real scanner failure) also
# blocks — fail closed.
SCAN_CMD="${SKILL_SCAN_CMD:-uvx snyk-agent-scan@0.5.10 --json}"

# --- Resolve the target to something scannable ------------------------------
scan_path=""
cleanup=""
if [[ -e "$target" ]]; then
  scan_path="$target"
elif [[ "$target" =~ ^https?://.*\.git$ || "$target" =~ ^git@ || "$target" =~ ^github: || "$target" =~ ^https?://github\.com/ ]]; then
  # Remote git source — shallow-clone to a temp dir, scan, then remove.
  tmp="$(mktemp -d)" || block "could not create temp dir for scan"
  url="$target"
  [[ "$url" =~ ^github:(.+)$ ]] && url="https://github.com/${BASH_REMATCH[1]}.git"
  if ! git clone --depth=1 "$url" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    block "could not fetch '$target' for pre-install scan"
  fi
  scan_path="$tmp"
  cleanup="$tmp"
else
  # Bare marketplace name — nothing local to scan before install.
  echo "skill-scan: '$target' has no local source to pre-scan; allowing install." >&2
  echo "  After install, scan with: ${SCAN_CMD} ~/.claude/plugins/<name>" >&2
  exit 0
fi

# --- Scan (fail closed) -----------------------------------------------------
# The default uvx scanner needs SNYK_TOKEN; refuse to proceed unscanned.
if [[ "$SCAN_CMD" == uvx* && -z "${SNYK_TOKEN:-}" ]]; then
  [[ -n "$cleanup" ]] && rm -rf "$cleanup"
  block "SNYK_TOKEN not set — cannot vet '$target' before install (add it to .env)"
fi

scan_bin="${SCAN_CMD%% *}"
if ! command -v "$scan_bin" >/dev/null 2>&1; then
  [[ -n "$cleanup" ]] && rm -rf "$cleanup"
  block "scanner '$scan_bin' not found — cannot vet '$target' before install"
fi

# shellcheck disable=SC2086
scan_out="$($SCAN_CMD "$scan_path" 2>/dev/null)"; scan_rc=$?
[[ -n "$cleanup" ]] && rm -rf "$cleanup"

# snyk-agent-scan's --json embeds raw control characters (un-escaped newlines in
# its reason/thought_process strings), which is technically invalid JSON and
# makes jq reject the whole document. Strip C0 control chars first — JSON
# doesn't need them structurally, so the result parses cleanly.
scan_json="$(printf '%s' "$scan_out" | tr -d '\000-\037')"

# Total issues reported across the result tree. Empty/garbage output (scanner
# crashed, no JSON) leaves $issues non-numeric -> fail closed below.
issues="$(jq '[.. | objects | select(has("issues")) | .issues | length] | add // 0' <<<"$scan_json" 2>/dev/null)"

if ! [[ "$issues" =~ ^[0-9]+$ ]]; then
  block "scanner returned no parseable result for '$target' (exit $scan_rc) — cannot vet, blocking"
fi

if (( issues > 0 )); then
  jq -r '.. | objects | select(has("issues")) | .issues[]
         | "  [\(.code) \(.extra_data.severity // "?")] \(.extra_data.title // .message)"' \
    <<<"$scan_json" >&2 2>/dev/null
  block "agent-scan flagged '$target' ($issues issue(s)) — install blocked"
fi

echo "skill-scan: '$target' passed agent-scan (0 issues)." >&2
exit 0
