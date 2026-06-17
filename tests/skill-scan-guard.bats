#!/usr/bin/env bats
# Tests for .claude/hooks/skill-scan-guard.sh
#
# The scanner is stubbed via SKILL_SCAN_CMD. The stub emits snyk-agent-scan
# `--json` output with STUB_ISSUES findings (default 0 = clean), so these run
# offline with no SNYK_TOKEN and no uvx/network dependency. The hook decides
# allow/block from the reported issue count, not the scanner's exit code.

setup() {
  HOOK="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.claude/hooks/skill-scan-guard.sh"
  WORKDIR="$(mktemp -d)"

  # Default: pretend we're on the work laptop unless a test overrides.
  hostname() { echo "Shuis-MacBook-Air"; }
  export -f hostname

  # Stub scanner: emits snyk-agent-scan --json with STUB_ISSUES findings
  # (default 0 = clean). Each finding's message carries a "stub-scan" marker so
  # tests can assert whether the scanner actually ran.
  STUB="$WORKDIR/scan-stub.sh"
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
n="${STUB_ISSUES:-0}"; issues=""; i=0
while [ "$i" -lt "$n" ]; do
  issues="${issues}{\"code\":\"E999\",\"message\":\"stub-scan finding $i\",\"extra_data\":{\"severity\":\"high\",\"title\":\"stub-scan finding $i\"}},"
  i=$((i+1))
done
printf '{"x":{"servers":[{"issues":[%s]}]}}\n' "${issues%,}"
exit "${STUB_RC:-0}"
EOF
  chmod +x "$STUB"
  export SKILL_SCAN_CMD="$STUB"
}

teardown() {
  rm -rf "$WORKDIR"
  unset -f hostname
}

# Feed a Bash command to the hook as PreToolUse JSON on stdin.
run_hook() {
  local cmd="$1" json
  json="$(jq -n --arg c "$cmd" '{tool_input: {command: $c}}')"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$HOOK"
}

@test "non-work host: install command is allowed without scanning" {
  hostname() { echo "personal-macbook-pro"; }
  export -f hostname
  mkdir -p "$WORKDIR/sk"
  export STUB_ISSUES=1   # scanner would block, but it must never run here
  run_hook "claude plugin install $WORKDIR/sk"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stub-scan"* ]]
}

@test "work host: non-install command passes through untouched" {
  export STUB_ISSUES=1
  run_hook "git status"
  [ "$status" -eq 0 ]
  [[ "$output" != *"stub-scan"* ]]
}

@test "work host: clean local target is allowed" {
  mkdir -p "$WORKDIR/myskill"
  export STUB_RC=0
  run_hook "claude plugin install $WORKDIR/myskill"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed agent-scan"* ]]
}

@test "work host: flagged local target is blocked" {
  mkdir -p "$WORKDIR/badskill"
  export STUB_ISSUES=1
  run_hook "claude plugin install $WORKDIR/badskill"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED (skill-scan)"* ]]
}

@test "work host: 'marketplace add' of a local path is scanned" {
  mkdir -p "$WORKDIR/mp"
  export STUB_ISSUES=1
  run_hook "claude plugin marketplace add $WORKDIR/mp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED (skill-scan)"* ]]
}

@test "work host: bare marketplace name is allowed with a scan reminder" {
  export STUB_ISSUES=1   # not scanned: nothing local to fetch
  run_hook "claude plugin install some-marketplace-plugin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no local source to pre-scan"* ]]
}

@test "work host: missing scanner binary fails closed (blocks)" {
  mkdir -p "$WORKDIR/sk"
  export SKILL_SCAN_CMD="/nonexistent/scanner-binary"
  run_hook "claude plugin install $WORKDIR/sk"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "work host: default uvx scanner without SNYK_TOKEN fails closed" {
  unset SKILL_SCAN_CMD   # fall back to the default `uvx snyk-agent-scan@latest --json`
  unset SNYK_TOKEN || true
  mkdir -p "$WORKDIR/sk"
  run_hook "claude plugin install $WORKDIR/sk"
  [ "$status" -eq 2 ]
  [[ "$output" == *"SNYK_TOKEN"* ]]
}

@test "work host: custom DOTFILES_WORK_HOSTNAME is honored" {
  export DOTFILES_WORK_HOSTNAME="custom-corp-laptop"
  hostname() { echo "custom-corp-laptop"; }
  export -f hostname
  mkdir -p "$WORKDIR/sk"
  export STUB_ISSUES=1
  run_hook "claude plugin install $WORKDIR/sk"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED (skill-scan)"* ]]
}

@test "work host: quoted local target is unwrapped and scanned" {
  mkdir -p "$WORKDIR/sk"
  export STUB_ISSUES=1
  run_hook "claude plugin install \"$WORKDIR/sk\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED (skill-scan)"* ]]
}

@test "work host: unparseable scanner output fails closed (blocks)" {
  # Scanner ran but emitted no JSON (e.g. crashed) -> cannot vet -> block.
  GARBAGE="$WORKDIR/garbage-scan.sh"
  cat > "$GARBAGE" <<'EOF'
#!/usr/bin/env bash
echo "boom: scanner exploded, not json"
exit 0
EOF
  chmod +x "$GARBAGE"
  export SKILL_SCAN_CMD="$GARBAGE"
  mkdir -p "$WORKDIR/sk"
  run_hook "claude plugin install $WORKDIR/sk"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no parseable result"* ]]
}
