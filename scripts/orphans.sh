#!/usr/bin/env bash
# Suggests orphaned dev processes (PPID=1, not system daemons) and optionally kills them.
# Usage: orphans.sh [-k]
#   -k   interactively prompt to kill each orphan

DEV_PATTERNS="node|npm|hugo|python[0-9.]?|ruby|rails|uvicorn|gunicorn|vite|webpack|next|nuxt|gatsby|cargo|go run|observable"

kill_mode=false
[[ "$1" == "-k" ]] && kill_mode=true

orphans=$(ps axo pid,ppid,command -m | awk '$2 == 1' | grep -E "$DEV_PATTERNS" | grep -v grep)

if [[ -z "$orphans" ]]; then
  echo "No orphaned dev processes found."
  exit 0
fi

echo "Orphaned dev processes (PPID=1):"
echo ""
printf "%-8s %s\n" "PID" "COMMAND"
printf "%-8s %s\n" "---" "-------"
while IFS= read -r line; do
  pid=$(awk '{print $1}' <<< "$line")
  cmd=$(awk '{$1=$2=""; sub(/^ +/, ""); print}' <<< "$line")
  printf "%-8s %.100s\n" "$pid" "$cmd"
done <<< "$orphans"

echo ""

if $kill_mode; then
  while IFS= read -r line; do
    pid=$(awk '{print $1}' <<< "$line")
    cmd=$(awk '{$1=$2=""; sub(/^ +/, ""); print}' <<< "$line" | cut -c1-60)
    printf "Kill %-8s %s? [y/N] " "$pid" "$cmd"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      kill "$pid" && echo "  killed $pid" || echo "  failed to kill $pid"
    fi
  done <<< "$orphans"
else
  pids=$(awk '{print $1}' <<< "$orphans" | tr '\n' ' ')
  echo "Run with -k to interactively kill, or:"
  echo "  kill $pids"
fi
