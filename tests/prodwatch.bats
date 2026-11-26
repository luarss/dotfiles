#!/usr/bin/env bats
# Tests for .config/swiftbar/prodwatch.60s.sh:
# Parsing and rendering of Claude and Antigravity usage metrics via ccusage --by-agent.

PRODWATCH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.config/swiftbar/prodwatch.60s.sh"

setup_file() {
  unset CLAUDE_CONFIG_DIR
  export QUIET_BIN="$BATS_FILE_TMPDIR/quiet-bin"
  export TODAY_COMPACT="$(date +%Y%m%d)"
  export TODAY_DASH="$(date +%Y-%m-%d)"
  mkdir -p "$QUIET_BIN"
  printf '#!/bin/bash\necho '\''{"daily":[{"agent":"all","totalCost":0,"totalTokens":0,"agents":[]}]}'\''\n' > "$QUIET_BIN/ccusage"
  printf '#!/bin/bash\nexit 0\n' > "$QUIET_BIN/gh"
  printf '#!/bin/bash\nexit 0\n' > "$QUIET_BIN/python3"
  printf '#!/bin/bash\nexit 0\n' > "$QUIET_BIN/ioreg"
  printf '#!/bin/bash\nexit 0\n' > "$QUIET_BIN/diskutil"
  printf '#!/bin/bash\nexit 1\n' > "$QUIET_BIN/df"
  chmod +x "$QUIET_BIN/ccusage" "$QUIET_BIN/gh" "$QUIET_BIN/python3" \
    "$QUIET_BIN/ioreg" "$QUIET_BIN/diskutil" "$QUIET_BIN/df"
}

setup() {
  TEST_DIR="$BATS_FILE_TMPDIR/t-$BATS_TEST_NUMBER"
}

stub_disk() {
  local stub_dir="$1" smart_status="$2" disk_free="$3" disk_used_percent="$4"
  printf '#!/bin/bash\n[ -n "%s" ] && echo "   SMART Status:              %s"\nexit 0\n' \
    "$smart_status" "$smart_status" > "$stub_dir/diskutil"
  printf '#!/bin/bash\n[ -n "%s" ] || exit 1\necho "Filesystem Size Used Avail Capacity iused ifree %%iused Mounted on"\necho "/dev/disk3s5 926Gi 800Gi %s %s%% 5.5M 1.3G 0%% /System/Volumes/Data"\n' \
    "$disk_free" "$disk_free" "$disk_used_percent" > "$stub_dir/df"
  chmod +x "$stub_dir/diskutil" "$stub_dir/df"
}

stub_github() {
  local stub_dir="$1" contributions="$2" prs="$3" remaining="$4" reset_at="${5:-2099-01-01T00:00:00Z}"
  printf '#!/bin/bash\necho call >> "%s/gh.calls"\nprintf '\''%%s\\n'\'' '\''{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"weeks":[{"contributionDays":[{"date":"2000-01-01","contributionCount":500},{"date":"%s","contributionCount":%s}]}]}}},"prsOpened":{"issueCount":%s},"authorOpened":{"nodes":[{"url":"o/r#1"},{"url":"o/r#2"}]},"assigneeOpened":{"nodes":[{"url":"o/r#2"},{"url":"o/r#3"}]},"authorClosed":{"nodes":[{"url":"o/r#5"}]},"assigneeClosed":{"nodes":[]},"rateLimit":{"remaining":%s,"resetAt":"%s"}}}'\''\n' \
    "$TEST_DIR" "$TODAY_DASH" "$contributions" "$prs" "$remaining" "$reset_at" > "$stub_dir/gh"
  chmod +x "$stub_dir/gh"
}

run_prodwatch() {
  if [ $# -gt 0 ]; then
    run env HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$QUIET_BIN:$PATH" \
      PRODWATCH_USAGE_POLL=0.05 "$@" bash "$PRODWATCH"
  else
    HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$QUIET_BIN:$PATH" \
      PRODWATCH_USAGE_POLL=0.05 run bash "$PRODWATCH"
  fi
}

setup_cold_home() {
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/work" "$TEST_DIR/home/projects"
}

setup_quiet_home() {
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/work" "$TEST_DIR/home/projects" "$TEST_DIR/home/.cache/prodwatch"
  printf '%s\n' '{"daily":[{"agent":"all","totalCost":0,"totalTokens":0,"agents":[]}]}' \
    > "$TEST_DIR/home/.cache/prodwatch/ccusage-${TODAY_COMPACT}.json"
}

stub_battery() {
  local stub_dir="$1" design="$2" nominal="$3" cycles="$4" failure="$5"
  cat > "$stub_dir/ioreg" <<STUB
#!/bin/bash
echo '      "CycleCount" = $cycles'
echo '      "DesignCapacity" = $design'
echo '      "NominalChargeCapacity" = $nominal'
echo '      "PermanentFailureStatus" = $failure'
STUB
  chmod +x "$stub_dir/ioreg"
}

# Helper to run the usage parser directly on a JSON string
parse_usage() {
  local json="$1"
  bash "$PRODWATCH" --parse-usage <<< "$json"
}

@test "parser handles Antigravity-only usage" {
  local json='{
    "daily": [{
      "agent": "all",
      "totalCost": 0.571,
      "totalTokens": 2444902,
      "agents": [{
        "agent": "antigravity",
        "totalCost": 0.571,
        "totalTokens": 2444902,
        "modelsUsed": ["gemini-3.8-flash-high"]
      }]
    }]
  }'
  run parse_usage "$json"
  [ "$status" -eq 0 ]
  read -r tot_cost tot_tok c_cost c_tok c_models a_cost a_tok a_models <<< "$output"
  [ "$tot_cost" = "0.57" ]
  [ "$tot_tok" = "2.4M" ]
  [ "$c_cost" = "0.00" ]
  [ "$c_tok" = "0" ]
  [ "$c_models" = "-" ]
  [ "$a_cost" = "0.57" ]
  [ "$a_tok" = "2.4M" ]
  [ "$a_models" = "3.8-flash-high" ]
}

@test "parser handles Claude-only usage" {
  local json='{
    "daily": [{
      "agent": "all",
      "totalCost": 12.34,
      "totalTokens": 1500000,
      "agents": [{
        "agent": "claude",
        "totalCost": 12.34,
        "totalTokens": 1500000,
        "modelsUsed": ["claude-3-5-sonnet-20241022"]
      }]
    }]
  }'
  run parse_usage "$json"
  [ "$status" -eq 0 ]
  read -r tot_cost tot_tok c_cost c_tok c_models a_cost a_tok a_models <<< "$output"
  [ "$tot_cost" = "12.34" ]
  [ "$tot_tok" = "1.5M" ]
  [ "$c_cost" = "12.34" ]
  [ "$c_tok" = "1.5M" ]
  [ "$c_models" = "3-5-sonnet" ]
  [ "$a_cost" = "0.00" ]
  [ "$a_tok" = "0" ]
  [ "$a_models" = "-" ]
}

@test "parser separates Claude and Antigravity and aggregates total" {
  local json='{
    "daily": [{
      "agent": "all",
      "totalCost": 15.50,
      "totalTokens": 3000000,
      "agents": [
        {
          "agent": "claude",
          "totalCost": 10.00,
          "totalTokens": 1000000,
          "modelsUsed": ["claude-sonnet-4-6"]
        },
        {
          "agent": "antigravity",
          "totalCost": 5.50,
          "totalTokens": 2000000,
          "modelsUsed": ["gemini-3.8-flash-high"]
        }
      ]
    }]
  }'
  run parse_usage "$json"
  [ "$status" -eq 0 ]
  read -r tot_cost tot_tok c_cost c_tok c_models a_cost a_tok a_models <<< "$output"
  [ "$tot_cost" = "15.50" ]
  [ "$tot_tok" = "3.0M" ]
  [ "$c_cost" = "10.00" ]
  [ "$c_tok" = "1.0M" ]
  [ "$c_models" = "sonnet-4-6" ]
  [ "$a_cost" = "5.50" ]
  [ "$a_tok" = "2.0M" ]
  [ "$a_models" = "3.8-flash-high" ]
}

@test "parser deduplicates models and preserves model versions" {
  local json='{
    "daily": [{
      "agent": "all",
      "totalCost": 2.00,
      "totalTokens": 50000,
      "agents": [
        {
          "agent": "claude",
          "totalCost": 1.00,
          "totalTokens": 25000,
          "modelsUsed": ["claude-opus-4-6", "claude-opus-4-6", "claude-3-5-sonnet-20241022"]
        },
        {
          "agent": "antigravity",
          "totalCost": 1.00,
          "totalTokens": 25000,
          "modelsUsed": ["gemini-3.8-flash", "gemini-3.8-flash-high", "gemini-3.8-flash"]
        }
      ]
    }]
  }'
  run parse_usage "$json"
  [ "$status" -eq 0 ]
  read -r tot_cost tot_tok c_cost c_tok c_models a_cost a_tok a_models <<< "$output"
  [ "$c_models" = "opus-4-6,3-5-sonnet" ]
  [ "$a_models" = "3.8-flash,3.8-flash-high" ]
}

@test "parser handles empty or invalid json gracefully" {
  run parse_usage "{}"
  [ "$status" -eq 0 ]
  [ "$output" = $'0.00\t0\t0.00\t0\t-\t0.00\t0\t-' ]

  run parse_usage "invalid json"
  [ "$status" -eq 0 ]
  [ "$output" = $'0.00\t0\t0.00\t0\t-\t0.00\t0\t-' ]
}

@test "prodwatch script outputs both Claude and Antigravity sections" {
  # Create a stub ccusage that returns both Claude and Antigravity
  setup_cold_home
  local stub_dir="$TEST_DIR/bin"
  cat > "$stub_dir/ccusage" <<'EOF'
#!/bin/bash
cat <<'JSON'
{
  "daily": [{
    "agent": "all",
    "totalCost": 5.57,
    "totalTokens": 2944902,
    "agents": [
      {
        "agent": "claude",
        "totalCost": 5.00,
        "totalTokens": 500000,
        "modelsUsed": ["claude-sonnet-4-6"]
      },
      {
        "agent": "antigravity",
        "totalCost": 0.57,
        "totalTokens": 2444902,
        "modelsUsed": ["gemini-3.8-flash-high"]
      }
    ]
  }]
}
JSON
EOF
  chmod +x "$stub_dir/ccusage"

  stub_github "$stub_dir" 77 25 4999

  cat > "$stub_dir/python3" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '45\t49\n'
EOF
  chmod +x "$stub_dir/python3"

  stub_disk "$stub_dir" "Verified" "124Gi" "87"

  # Run prodwatch with empty WORK/PROJECTS and stubbed ccusage
  run_prodwatch
  [ "$status" -eq 0 ]

  # Check menubar header (three cycling title lines): commits + issues, cost/tokens, temp/disk
  [[ "$output" =~ "<> 77 · PR 25 | font=Menlo size=13" ]]
  [[ "$output" =~ "🐛 ↑3/↓1 | font=Menlo size=13" ]]
  [[ "$output" =~ "GitHub today · 77 contributions · 25 PRs | font=Menlo" ]]
  [[ "$output" =~ "45°C · 💾 13% free | font=Menlo size=13" ]]
  [[ "$output" =~ "SoC temp · avg 45°C · max 49°C | font=Menlo" ]]
  [[ "$output" =~ "Disk · SMART Verified · 124Gi free (13%) | font=Menlo" ]]
  [[ ! "$output" =~ "⚠️ disk" ]]
  [[ "$output" =~ "\$5.57 · 2.9M | font=Menlo size=13" ]]

  # Check issues dropdown section
  [[ "$output" =~ "Issues today · ↑3 opened · ↓1 closed | font=Menlo" ]]

  # Check Claude section
  [[ "$output" =~ "Claude today · \$5.00 · 500k tok | font=Menlo" ]]
  [[ "$output" =~ "models: sonnet-4-6 | font=Menlo size=12 color=gray" ]]

  # Check Antigravity section
  [[ "$output" =~ "Antigravity today · \$0.57 · 2.4M tok | font=Menlo" ]]
  [[ "$output" =~ "models: 3.8-flash-high | font=Menlo size=12 color=gray" ]]
}

@test "prodwatch shows zero issue counts when gh returns nothing" {
  setup_quiet_home
  stub_disk "$TEST_DIR/bin" "Verified" "124Gi" "87"

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 0 | font=Menlo size=13" ]]
  [[ "$output" =~ "🐛 ↑0/↓0 | font=Menlo size=13" ]]
  [[ "$output" =~ "Issues today · ↑0 opened · ↓0 closed | font=Menlo" ]]
  [[ ! "$output" =~ "°C" ]]
}

@test "prodwatch flags a failing SMART status in red and in the title" {
  setup_quiet_home
  stub_disk "$TEST_DIR/bin" "Failing" "124Gi" "50"

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "💾 50% free · ⚠️ disk | font=Menlo size=13" ]]
  [[ "$output" =~ "Disk · SMART Failing · 124Gi free (50%) | font=Menlo color=red" ]]
}

@test "prodwatch flags a disk over 90% full" {
  setup_quiet_home
  stub_disk "$TEST_DIR/bin" "Verified" "40Gi" "96"

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "💾 4% free · ⚠️ disk | font=Menlo size=13" ]]
  [[ "$output" =~ "Disk · SMART Verified · 40Gi free (4%) | font=Menlo color=red" ]]
}

@test "prodwatch omits the disk line when disk tools return nothing" {
  setup_quiet_home

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 0 | font=Menlo size=13" ]]
  [[ "$output" =~ "🐛 ↑0/↓0 | font=Menlo size=13" ]]
  [[ ! "$output" =~ "Disk ·" ]]
  [[ ! "$output" =~ "💾" ]]
}

@test "prodwatch shows battery health and cycle count" {
  setup_quiet_home
  stub_battery "$TEST_DIR/bin" 4629 4456 63 0

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Battery · 96% health · 63 cycles | font=Menlo" ]]
  [[ ! "$output" =~ "⚠️ battery" ]]
  [[ ! "$output" =~ "63 cycles | font=Menlo color=red" ]]
}

@test "prodwatch flags battery health below 80% in red and in the title" {
  setup_quiet_home
  stub_battery "$TEST_DIR/bin" 5000 3900 812 0

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "⚠️ battery | font=Menlo size=13" ]]
  [[ "$output" =~ "Battery · 78% health · 812 cycles | font=Menlo color=red" ]]
}

@test "prodwatch flags a battery permanent failure" {
  setup_quiet_home
  stub_battery "$TEST_DIR/bin" 4629 4456 63 1

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Battery · 96% health · 63 cycles | font=Menlo color=red" ]]
}

@test "prodwatch omits the battery line when ioreg reports no battery" {
  setup_quiet_home

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "Battery ·" ]]
}

stub_counting_ccusage() {
  local stub_dir="$1" cost="$2"
  cat > "$stub_dir/ccusage" <<EOF2
#!/bin/bash
echo call >> "$TEST_DIR/ccusage.calls"
echo '{"daily":[{"agent":"all","totalCost":$cost,"totalTokens":0,"agents":[]}]}'
EOF2
  chmod +x "$stub_dir/ccusage"
}

@test "prodwatch reuses a fresh ccusage cache instead of re-running ccusage" {
  setup_cold_home
  stub_counting_ccusage "$TEST_DIR/bin" 1.25

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$1.25 · 0 | font=Menlo size=13" ]]

  stub_counting_ccusage "$TEST_DIR/bin" 9.99
  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$1.25 · 0 | font=Menlo size=13" ]]
  [ "$(wc -l < "$TEST_DIR/ccusage.calls")" -eq 1 ]
}

@test "prodwatch re-runs ccusage once the cache is older than the TTL" {
  setup_cold_home
  stub_counting_ccusage "$TEST_DIR/bin" 1.25

  run_prodwatch
  [ "$status" -eq 0 ]

  stub_counting_ccusage "$TEST_DIR/bin" 9.99
  run_prodwatch PRODWATCH_CCUSAGE_TTL=0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$9.99 · 0 | font=Menlo size=13" ]]
  [ "$(wc -l < "$TEST_DIR/ccusage.calls")" -eq 2 ]
}

seed_usage_cache() {
  local cost="$1"
  mkdir -p "$TEST_DIR/home/.cache/prodwatch"
  printf '%s\n' "{\"daily\":[{\"agent\":\"all\",\"totalCost\":$cost,\"totalTokens\":0,\"agents\":[]}]}" \
    > "$TEST_DIR/home/.cache/prodwatch/ccusage-${TODAY_COMPACT}.json"
}

seed_github_cache() {
  local contributions="$1" prs="$2" remaining="$3" reset_at="${4:-2099-01-01T00:00:00Z}"
  mkdir -p "$TEST_DIR/home/.cache/prodwatch"
  cat > "$TEST_DIR/home/.cache/prodwatch/github-${TODAY_COMPACT}.json" <<EOF
{"data":{
  "viewer":{"contributionsCollection":{"contributionCalendar":{"weeks":[{"contributionDays":[
    {"date":"2000-01-01","contributionCount":500},
    {"date":"$TODAY_DASH","contributionCount":$contributions}]}]}}},
  "prsOpened":{"issueCount":$prs},
  "authorOpened":{"nodes":[{"url":"o/r#1"},{"url":"o/r#2"}]},
  "assigneeOpened":{"nodes":[{"url":"o/r#2"},{"url":"o/r#3"}]},
  "authorClosed":{"nodes":[{"url":"o/r#5"}]},
  "assigneeClosed":{"nodes":[]},
  "rateLimit":{"remaining":$remaining,"resetAt":"$reset_at"}
}}
EOF
}

@test "prodwatch keeps the last good cache when ccusage fails" {
  setup_cold_home
  seed_usage_cache 1.25

  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/bin/ccusage"
  chmod +x "$TEST_DIR/bin/ccusage"
  run_prodwatch PRODWATCH_CCUSAGE_TTL=0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$1.25 · 0 | font=Menlo size=13" ]]
}

@test "prodwatch keeps the last good cache when ccusage prices models at zero" {
  setup_cold_home
  seed_usage_cache 1.25

  cat > "$TEST_DIR/bin/ccusage" <<'EOF'
#!/bin/bash
echo '{"daily":[{"agent":"all","totalCost":0.5,"totalTokens":1000,"agents":[{"agent":"claude","totalCost":0,"totalTokens":1000,"modelBreakdowns":[{"modelName":"claude-new","inputTokens":10,"outputTokens":10,"cacheCreationTokens":0,"cacheReadTokens":980,"cost":0}]}]}]}'
EOF
  chmod +x "$TEST_DIR/bin/ccusage"
  run_prodwatch PRODWATCH_CCUSAGE_TTL=0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$1.25 · 0 | font=Menlo size=13" ]]
}

@test "prodwatch accepts reports whose only unpriced model is a ccusage placeholder" {
  setup_cold_home
  cat > "$TEST_DIR/bin/ccusage" <<'EOF'
#!/bin/bash
echo '{"daily":[{"agent":"all","totalCost":0.32,"totalTokens":3000000,"agents":[{"agent":"antigravity","totalCost":0.32,"totalTokens":3000000,"modelsUsed":["gemini-3.6-flash-low","model_placeholder_m437"],"modelBreakdowns":[{"modelName":"gemini-3.6-flash-low","inputTokens":1000,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"cost":0.32},{"modelName":"model_placeholder_m437","inputTokens":2000,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"cost":0}]}]}]}'
EOF
  chmod +x "$TEST_DIR/bin/ccusage"

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Antigravity today · \$0.32 · 3.0M tok" ]]
}

@test "prodwatch renders without waiting for a slow ccusage and caches its result later" {
  setup_cold_home
  cat > "$TEST_DIR/bin/ccusage" <<'EOF'
#!/bin/bash
sleep 0.8
echo '{"daily":[{"agent":"all","totalCost":4.5,"totalTokens":0,"agents":[]}]}'
EOF
  chmod +x "$TEST_DIR/bin/ccusage"

  SECONDS=0
  run_prodwatch PRODWATCH_USAGE_WAIT=0
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 2 ]
  [[ ! "$output" =~ "\$4.50" ]]

  local waited=0
  while [ -d "$TEST_DIR/home/.cache/prodwatch/ccusage.lock" ] && [ "$waited" -lt 100 ]; do
    sleep 0.05
    waited=$((waited + 1))
  done
  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$4.50 · 0 | font=Menlo size=13" ]]
  [ -z "$(find "$TEST_DIR/home/.cache/prodwatch" -name 'ccusage.??????')" ]
}

stub_profile_ccusage() {
  local stub_dir="$1" default_report="$2" alt_report="$3"
  cat > "$stub_dir/ccusage" <<EOF2
#!/bin/bash
echo "\$CLAUDE_CONFIG_DIR \$*" >> "$TEST_DIR/ccusage.calls"
if [ "\$1" = claude ]; then
  echo '$alt_report'
else
  echo '$default_report'
fi
EOF2
  chmod +x "$stub_dir/ccusage"
}

@test "prodwatch adds alt profile usage to the Claude agent" {
  setup_cold_home
  mkdir -p "$TEST_DIR/home/.claude-alt-profile/projects"
  stub_profile_ccusage "$TEST_DIR/bin" \
    '{"daily":[{"agent":"all","totalCost":1.5,"totalTokens":3000,"agents":[{"agent":"claude","totalCost":1.0,"totalTokens":2000,"modelsUsed":["claude-opus-5-5"]},{"agent":"antigravity","totalCost":0.5,"totalTokens":1000,"modelsUsed":["gemini-3"]}]}]}' \
    '{"daily":[{"date":"today","totalCost":2.25,"totalTokens":5000,"modelsUsed":["claude-sonnet-5-5"]}]}'

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$3.75 · 8k | font=Menlo size=13" ]]
  [[ "$output" =~ "Claude today · \$3.25 · 7k tok" ]]
  [[ "$output" =~ "models: opus-5-5,sonnet-5-5" ]]
  [[ "$output" =~ "Antigravity today · \$0.50 · 1k tok" ]]
  grep -q "^$TEST_DIR/home/.claude-alt-profile claude daily" "$TEST_DIR/ccusage.calls"
}

@test "prodwatch shows alt profile usage when the default profile is idle" {
  setup_cold_home
  mkdir -p "$TEST_DIR/home/.claude-alt-profile/projects"
  stub_profile_ccusage "$TEST_DIR/bin" \
    '{"daily":[]}' \
    '{"daily":[{"date":"today","totalCost":2.25,"totalTokens":5000,"modelsUsed":["claude-opus-5-5"]}]}'

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\$2.25 · 5k | font=Menlo size=13" ]]
  [[ "$output" =~ "Claude today · \$2.25 · 5k tok" ]]
}

@test "prodwatch skips the alt profile when it does not exist" {
  setup_cold_home
  stub_profile_ccusage "$TEST_DIR/bin" \
    '{"daily":[{"agent":"all","totalCost":1.0,"totalTokens":2000,"agents":[{"agent":"claude","totalCost":1.0,"totalTokens":2000}]}]}' \
    '{"daily":[{"totalCost":99,"totalTokens":99}]}'

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Claude today · \$1.00 · 2k tok" ]]
  ! grep -q " claude daily" "$TEST_DIR/ccusage.calls"
}

@test "prodwatch tracks the identity from the identity file" {
  setup_quiet_home
  local repo="$TEST_DIR/home/work/office-repo"
  mkdir -p "$repo" "$TEST_DIR/home/.config/prodwatch"
  printf '%s\n' "PRODWATCH_WORK_AUTHOR=NUSXGrok" "PRODWATCH_PROJ_AUTHOR=NUSXGrok" "PRODWATCH_GITHUB_USER=NUSXGrok" \
    > "$TEST_DIR/home/.config/prodwatch/identity"
  git -C "$repo" init -q
  echo hi > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" -c user.name=NUSXGrok -c user.email=bot@example.com commit -qm one
  echo hi > "$repo/other"
  git -C "$repo" add other
  git -C "$repo" -c user.name=luarss -c user.email=song.luar@a5x.ai commit -qm two

  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "github.com/NUSXGrok" ]]
  [[ "$output" =~ "office-repo" ]]
  [[ "$output" =~ "<> 1 |" ]]
}

@test "prodwatch falls back to local commit count when GitHub has no data" {
  setup_quiet_home
  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 0 | font=Menlo size=13" ]]
  [[ "$output" =~ "🐛 ↑0/↓0 | font=Menlo size=13" ]]
  [[ ! "$output" =~ "GitHub today" ]]
}

@test "prodwatch reuses a fresh GitHub cache instead of calling the API" {
  setup_quiet_home
  stub_github "$TEST_DIR/bin" 7 1 4999
  run_prodwatch
  [ "$status" -eq 0 ]

  stub_github "$TEST_DIR/bin" 99 9 4999
  run_prodwatch
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 7 · PR 1 |" ]]
  [ "$(wc -l < "$TEST_DIR/gh.calls")" -eq 1 ]
}

@test "prodwatch refetches GitHub once the cache is older than the TTL" {
  setup_quiet_home
  stub_github "$TEST_DIR/bin" 7 1 4999
  run_prodwatch
  stub_github "$TEST_DIR/bin" 99 9 4999
  run_prodwatch PRODWATCH_GH_TTL=0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 99 · PR 9 |" ]]
  [ "$(wc -l < "$TEST_DIR/gh.calls")" -eq 2 ]
}

@test "prodwatch keeps the last good GitHub cache when the API fails" {
  setup_quiet_home
  seed_github_cache 7 1 4999
  printf '#!/bin/bash\necho "{\\"errors\\":[{\\"type\\":\\"RATE_LIMITED\\"}]}"\nexit 1\n' > "$TEST_DIR/bin/gh"
  chmod +x "$TEST_DIR/bin/gh"
  run_prodwatch PRODWATCH_GH_TTL=0
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 7 · PR 1 |" ]]
}

@test "prodwatch stops calling GitHub while the rate budget is low" {
  setup_quiet_home
  seed_github_cache 7 1 100
  stub_github "$TEST_DIR/bin" 7 1 100
  run_prodwatch PRODWATCH_GH_TTL=0
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_DIR/gh.calls" ]
}

@test "prodwatch resumes calling GitHub after the rate limit resets" {
  setup_quiet_home
  seed_github_cache 7 1 100 "2000-01-01T00:00:00Z"
  stub_github "$TEST_DIR/bin" 7 1 100 "2000-01-01T00:00:00Z"
  run_prodwatch PRODWATCH_GH_TTL=0
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_DIR/gh.calls")" -eq 1 ]
}
