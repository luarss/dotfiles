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

  # Run prodwatch with empty WORK/PROJECTS and stubbed ccusage
  local fake_home="$TEST_DIR/home"
  mkdir -p "$fake_home/work" "$fake_home/projects"

  run env HOME="$fake_home" PATH="$stub_dir:$PATH" bash "$PRODWATCH"
  [ "$status" -eq 0 ]

  # Check menubar header has aggregate total
  [[ "$output" =~ "⚡ 0cmmt · \$5.57 · 2.9M | font=Menlo size=13" ]]

  # Check Claude section
  [[ "$output" =~ "Claude today · \$5.00 · 500k tok | font=Menlo" ]]
  [[ "$output" =~ "models: sonnet-4-6 | font=Menlo size=12 color=gray" ]]

  # Check Antigravity section
  [[ "$output" =~ "Antigravity today · \$0.57 · 2.4M tok | font=Menlo" ]]
  [[ "$output" =~ "models: 3.8-flash-high | font=Menlo size=12 color=gray" ]]
}
