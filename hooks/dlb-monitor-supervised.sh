#!/usr/bin/env bash
# Supervised dlb-monitor wrapper.
#
# WHY: dlb-monitor (the DLB wake source) exits on crash, script error (observed
# exit 127), or watchdog timeout, and historically a human had to notice the dead
# monitor and type "restart your dlb monitor" (~10x/week — see the 2026-07-17
# harness review, finding F6). This wrapper respawns the child automatically so a
# crashed/exited monitor self-heals. Each respawn emits a stdout line, which the
# Monitor tool surfaces as an event, so respawns are visible.
#
# NOTE: this heals the *child-exit* case. It does NOT survive the Monitor task
# itself being killed by context compaction / session teardown — that still needs
# a SessionStart re-launch. Launch this exactly where you'd launch dlb-monitor:
#   Monitor({command: "~/.claude/hooks/dlb-monitor-supervised.sh --name <dlb-name>", persistent: true})
#
# Usage: dlb-monitor-supervised.sh --name <dlb-name> [extra dlb-monitor args...]
set -uo pipefail

MON="$(command -v dlb-monitor || echo "$HOME/.local/bin/dlb-monitor")"
NAME="?"
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--name" && $((i+1)) -lt ${#args[@]} ]]; then
    NAME="${args[$((i+1))]}"
  fi
done

if [[ ! -x "$MON" ]]; then
  echo "[supervisor] dlb-monitor not found at '$MON' — install with: uv tool install dlb-mcp"
  exit 127
fi

backoff=2
while true; do
  "$MON" "${args[@]}"
  code=$?
  echo "[supervisor] dlb-monitor(${NAME}) exited code=${code}; respawning in ${backoff}s"
  sleep "$backoff"
  if (( backoff < 30 )); then backoff=$(( backoff * 2 )); fi
done
