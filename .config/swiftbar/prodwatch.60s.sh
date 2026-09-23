#!/bin/bash
# SwiftBar productivity widget: today's git activity + Claude/Antigravity usage.
# Refreshes every 60s (filename ".60s."). Deliberately lightweight: one git
# pass per repo, one node call, active repos only.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"

WORK="$HOME/work"
PROJECTS="$HOME/projects"
SINCE="$(date +%Y-%m-%dT00:00:00)"
# --author is a regex; \| alternation lets one scan match several identities.
WORK_AUTHOR="song.luar@a5x.ai"
# ~/projects repos commit under the personal GitHub noreply identity too.
PROJ_AUTHOR="song.luar@a5x.ai\|luarss@users.noreply.github.com"

# Kick off ccusage (the slow half) in the background so it overlaps the git scan.
USAGE_RAW="$(mktemp)"
( ccusage daily --json --by-agent --since "$(date +%Y%m%d)" >"$USAGE_RAW" 2>/dev/null ) &
USAGE_PID=$!

# --- Git: scan a base dir; one numstat pass per repo, count commits + sum lines.
# Populates globals: g_commits g_add g_del g_rows (safe if $1 doesn't exist —
# the unmatched glob fails the .git guard and the loop body is skipped).
scan_repos() {
  local base="$1" author="$2" d c a del
  g_commits=0; g_add=0; g_del=0; g_rows=""
  for d in "$base"/*/; do
    [ -d "$d/.git" ] || continue
    read -r c a del < <(git -C "$d" log --since="$SINCE" --author="$author" \
        --pretty=format:'C' --numstat 2>/dev/null \
        | awk '/^C/{c++} NF==3{a+=$1;del+=$2} END{print c+0, a+0, del+0}')
    [ "${c:-0}" -gt 0 ] || continue
    g_commits=$((g_commits + c)); g_add=$((g_add + a)); g_del=$((g_del + del))
    g_rows+="$(basename "$d")"$'\t'"$c"$'\t'"$a"$'\t'"$del"$'\n'
  done
}

scan_repos "$WORK" "$WORK_AUTHOR"
work_commits=$g_commits; work_add=$g_add; work_del=$g_del; work_rows=$g_rows
scan_repos "$PROJECTS" "$PROJ_AUTHOR"
proj_commits=$g_commits; proj_add=$g_add; proj_del=$g_del; proj_rows=$g_rows

total_commits=$((work_commits + proj_commits))

# --- Claude & Antigravity usage today: one node call returns tab-delimited metrics ---
wait "$USAGE_PID" 2>/dev/null
read -r tot_cost tot_htok c_cost c_htok c_models a_cost a_htok a_models < <(node -e '
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
});' 2>/dev/null < "$USAGE_RAW")
rm -f "$USAGE_RAW"
tot_cost="${tot_cost:-0.00}"; tot_htok="${tot_htok:-0}"
c_cost="${c_cost:-0.00}"; c_htok="${c_htok:-0}"; c_models="${c_models:--}"
a_cost="${a_cost:-0.00}"; a_htok="${a_htok:-0}"; a_models="${a_models:--}"

# --- Render a "base<TAB>commits<TAB>add<TAB>del" repo table under a heading ---
print_section() {
  local title="$1" base="$2" commits="$3" add="$4" del="$5" rows="$6"
  echo "${title} · ${commits} commits · +${add}/-${del} | font=Menlo"
  if [ -n "${rows//[$'\n\t']/}" ]; then
    printf '%s' "$rows" | while IFS=$'\t' read -r name c a d; do
      [ -n "$name" ] || continue
      printf '%s  %scmmt  +%s/-%s | font=Menlo size=12 href=file://%s/%s\n' "$name" "$c" "$a" "$d" "$base" "$name"
    done
  else
    echo "— no commits yet today | font=Menlo size=12 color=gray"
  fi
}

# ================= SwiftBar output =================
echo "⚡ ${total_commits}cmmt · \$${tot_cost} · ${tot_htok} | font=Menlo size=13"
echo "---"
print_section "Work today" "$WORK" "$work_commits" "$work_add" "$work_del" "$work_rows"
echo "---"
print_section "Projects today" "$PROJECTS" "$proj_commits" "$proj_add" "$proj_del" "$proj_rows"
echo "---"
echo "Claude today · \$${c_cost} · ${c_htok} tok | font=Menlo"
[ "$c_models" != "-" ] && echo "models: ${c_models} | font=Menlo size=12 color=gray"
echo "Antigravity today · \$${a_cost} · ${a_htok} tok | font=Menlo"
[ "$a_models" != "-" ] && echo "models: ${a_models} | font=Menlo size=12 color=gray"
echo "github.com/luarss | font=Menlo size=12 href=https://github.com/luarss"
echo "---"
echo "Updated $(date +%H:%M) | size=11 color=gray"
echo "Refresh | refresh=true"
