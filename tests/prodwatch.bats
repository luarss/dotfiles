#!/usr/bin/env bats
# Tests for .config/swiftbar/prodwatch.60s.sh:
# Parsing and rendering of Claude and Antigravity usage metrics via ccusage --by-agent.

PRODWATCH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/.config/swiftbar/prodwatch.60s.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

stub_disk() {
  local stub_dir="$1" smart_status="$2" disk_free="$3" disk_used_percent="$4"
  cat > "$stub_dir/diskutil" <<EOF
#!/bin/bash
[ -n "$smart_status" ] && echo "   SMART Status:              $smart_status"
exit 0
EOF
  cat > "$stub_dir/df" <<EOF
#!/bin/bash
[ -n "$disk_free" ] || exit 1
echo "Filesystem Size Used Avail Capacity iused ifree %iused Mounted on"
echo "/dev/disk3s5 926Gi 800Gi $disk_free ${disk_used_percent}% 5.5M 1.3G 0% /System/Volumes/Data"
EOF
  chmod +x "$stub_dir/diskutil" "$stub_dir/df"
}

stub_quiet_sources() {
  local stub_dir="$1"
  cat > "$stub_dir/ccusage" <<'EOF'
#!/bin/bash
echo '{"daily":[{"agent":"all","totalCost":0,"totalTokens":0,"agents":[]}]}'
EOF
  printf '#!/bin/bash\nexit 0\n' > "$stub_dir/gh"
  printf '#!/bin/bash\ncat >/dev/null\n' > "$stub_dir/python3"
  chmod +x "$stub_dir/ccusage" "$stub_dir/gh" "$stub_dir/python3"
}

# Helper to run the node parser snippet directly on a JSON string
parse_usage() {
  local json="$1"
  node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{
    const json=JSON.parse(s);
    const t=json.daily?.slice(-1)[0];
    if(!t){console.log("0.00\t0\t0.00\t0\t-\t0.00\t0\t-");return;}
    const fmtTok = n => {
      n = Number(n) || 0;
      return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(0) + "k" : "" + n;
    };
    const cleanModels = list => {
      const cleaned = (list || [])
        .map(x => x.replace(/^(claude|gemini)-/, "").replace(/-\d{8}$/, ""))
        .filter(Boolean);
      return [...new Set(cleaned)].join(",") || "-";
    };

    const agents = Array.isArray(t.agents) ? t.agents : [];
    let c = agents.find(x => x.agent === "claude" || x.agent?.toLowerCase() === "claude");
    let a = agents.find(x => x.agent === "antigravity" || x.agent?.toLowerCase() === "antigravity");

    if (!c && !a && t.metadata?.agents) {
      if (t.metadata.agents.includes("claude") && !t.metadata.agents.includes("antigravity")) c = t;
      else if (t.metadata.agents.includes("antigravity") && !t.metadata.agents.includes("claude")) a = t;
    }

    const cCost = Number(c?.totalCost || 0).toFixed(2);
    const cTok = fmtTok(c?.totalTokens);
    const cModels = cleanModels(c?.modelsUsed);

    const aCost = Number(a?.totalCost || 0).toFixed(2);
    const aTok = fmtTok(a?.totalTokens);
    const aModels = cleanModels(a?.modelsUsed);

    const totCost = Number(t.totalCost || 0).toFixed(2);
    const totTok = fmtTok(t.totalTokens);

    console.log([totCost, totTok, cCost, cTok, cModels, aCost, aTok, aModels].join("\t"));
  }catch(e){console.log("0.00\t0\t0.00\t0\t-\t0.00\t0\t-");}
});' <<< "$json"
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
  local stub_dir="$TEST_DIR/bin"
  mkdir -p "$stub_dir"
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

  # Stub gh so issue counts are deterministic and no network call is made.
  # Emulates `gh search issues ... -q ...` by printing repo#number keys directly.
  # author-opened {1,2} ∪ assignee-opened {2,3} → 3 distinct opened (dedup on #2);
  # author-closed {5} ∪ assignee-closed {} → 1 closed.
  cat > "$stub_dir/gh" <<'EOF'
#!/bin/bash
args="$*"
if [[ "$args" == *"--created"* ]]; then
  if [[ "$args" == *"--author"* ]]; then printf 'o/r#1\no/r#2\n'
  else printf 'o/r#2\no/r#3\n'; fi
elif [[ "$args" == *"--closed"* ]]; then
  if [[ "$args" == *"--author"* ]]; then printf 'o/r#5\n'; fi
fi
EOF
  chmod +x "$stub_dir/gh"

  cat > "$stub_dir/python3" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '45\t49\n'
EOF
  chmod +x "$stub_dir/python3"

  stub_disk "$stub_dir" "Verified" "124Gi" "87"

  # Run prodwatch with empty WORK/PROJECTS and stubbed ccusage
  local fake_home="$TEST_DIR/home"
  mkdir -p "$fake_home/work" "$fake_home/projects"

  run env HOME="$fake_home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]

  # Check menubar header (three cycling title lines): commits + issues, cost/tokens, temp/disk
  [[ "$output" =~ "<> 0 · 🐛 ↑3/↓1 | font=Menlo size=13" ]]
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
  local stub_dir="$TEST_DIR/bin"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/ccusage" <<'EOF'
#!/bin/bash
echo '{"daily":[{"agent":"all","totalCost":0,"totalTokens":0,"agents":[]}]}'
EOF
  chmod +x "$stub_dir/ccusage"

  # gh present but authed to nothing today → empty output on every search
  cat > "$stub_dir/gh" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$stub_dir/gh"

  cat > "$stub_dir/python3" <<'EOF'
#!/bin/bash
cat >/dev/null
EOF
  chmod +x "$stub_dir/python3"

  stub_disk "$stub_dir" "Verified" "124Gi" "87"

  local fake_home="$TEST_DIR/home"
  mkdir -p "$fake_home/work" "$fake_home/projects"

  run env HOME="$fake_home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 0 · 🐛 ↑0/↓0 | font=Menlo size=13" ]]
  [[ "$output" =~ "Issues today · ↑0 opened · ↓0 closed | font=Menlo" ]]
  [[ ! "$output" =~ "°C" ]]
}

@test "prodwatch flags a failing SMART status in red and in the title" {
  local stub_dir="$TEST_DIR/bin"
  mkdir -p "$stub_dir" "$TEST_DIR/home/work" "$TEST_DIR/home/projects"
  stub_quiet_sources "$stub_dir"
  stub_disk "$stub_dir" "Failing" "124Gi" "50"

  run env HOME="$TEST_DIR/home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "💾 50% free · ⚠️ disk | font=Menlo size=13" ]]
  [[ "$output" =~ "Disk · SMART Failing · 124Gi free (50%) | font=Menlo color=red" ]]
}

@test "prodwatch flags a disk over 90% full" {
  local stub_dir="$TEST_DIR/bin"
  mkdir -p "$stub_dir" "$TEST_DIR/home/work" "$TEST_DIR/home/projects"
  stub_quiet_sources "$stub_dir"
  stub_disk "$stub_dir" "Verified" "40Gi" "96"

  run env HOME="$TEST_DIR/home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "💾 4% free · ⚠️ disk | font=Menlo size=13" ]]
  [[ "$output" =~ "Disk · SMART Verified · 40Gi free (4%) | font=Menlo color=red" ]]
}

@test "prodwatch omits the disk line when disk tools return nothing" {
  local stub_dir="$TEST_DIR/bin"
  mkdir -p "$stub_dir" "$TEST_DIR/home/work" "$TEST_DIR/home/projects"
  stub_quiet_sources "$stub_dir"
  stub_disk "$stub_dir" "" "" ""

  run env HOME="$TEST_DIR/home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<> 0 · 🐛 ↑0/↓0 | font=Menlo size=13" ]]
  [[ ! "$output" =~ "Disk ·" ]]
  [[ ! "$output" =~ "💾" ]]
}
