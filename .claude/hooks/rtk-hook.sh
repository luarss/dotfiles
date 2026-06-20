#!/usr/bin/env bash
# Wraps `rtk hook claude` for the PreToolUse hook.
# No-ops on non-Darwin so Linux machines aren't broken by a missing rtk binary.
[[ "$(uname)" == "Darwin" ]] || exit 0
exec rtk hook claude
