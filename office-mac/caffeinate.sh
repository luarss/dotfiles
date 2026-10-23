#!/usr/bin/env bash
# Keep the office Mac (and its display) awake for 7 days, even while locked.
# Replaces any caffeinate already running so reruns don't stack.
# The lid must stay open, and on battery -s has no effect.
set -euo pipefail

pkill -x caffeinate 2>/dev/null || true
nohup caffeinate -dims -t 604800 >/dev/null 2>&1 &
echo "caffeinate running (pid $!) for 7 days"
