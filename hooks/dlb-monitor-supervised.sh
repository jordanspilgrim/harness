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
# UPGRADES: dlb-monitor (dlb-mcp 0.7.2+) exits with code 75 when it sees a newer
# dlb-mcp installed on disk. The wrapper respawns it at once, with no backoff, so
# the monitor runs the new code without a session restart.
#
# ONE PER NAME: a second wrapper for a name that already has a live one exits
# instead of starting a duplicate monitor. The lock lives outside ~/.dlb, at
# ${TMPDIR:-/tmp}/dlb-monitor-supervised/<name>.lock, and holds the owner's pid.
# A lock whose pid is gone, or is no longer this script, is stale and taken over.
# The wrapper also exits when its parent dies (it was orphaned), so a dead
# session cannot hold the lock and block the next one.
#
# Usage: dlb-monitor-supervised.sh --name <dlb-name> [extra dlb-monitor args...]
set -uo pipefail

EXIT_VERSION_CHANGED=75

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

# --- one live wrapper per name -------------------------------------------
LOCK_DIR=""
release_lock() {
  if [[ -n "$LOCK_DIR" && "$(cat "$LOCK_DIR/pid" 2>/dev/null)" == "$$" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

lock_owner_alive() {
  # The pid is live AND still this script (guards against pid reuse).
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q "dlb-monitor-supervised"
}

if [[ "$NAME" != "?" ]]; then
  lock_root="${TMPDIR:-/tmp}"
  lock_root="${lock_root%/}/dlb-monitor-supervised"
  mkdir -p "$lock_root"
  # DLB names are already path-safe, but keep the path safe whatever was passed.
  LOCK_DIR="$lock_root/$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '_').lock"
  for _ in 1 2 3; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "$$" > "$LOCK_DIR/pid"
      break
    fi
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -z "$owner" ]]; then
      # Another wrapper may be between its mkdir and writing its pid.
      sleep 1
      owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
    fi
    if lock_owner_alive "$owner"; then
      echo "[supervisor] dlb-monitor(${NAME}) already supervised by pid ${owner}; not starting a duplicate"
      exit 0
    fi
    echo "[supervisor] dlb-monitor(${NAME}) clearing stale lock (pid ${owner:-none})"
    rm -rf "$LOCK_DIR"
  done
  if [[ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" != "$$" ]]; then
    echo "[supervisor] dlb-monitor(${NAME}) could not take the lock at ${LOCK_DIR}"
    exit 1
  fi
fi

child=""
cleanup() {
  if [[ -n "$child" ]]; then kill "$child" 2>/dev/null; fi
  release_lock
}
trap cleanup EXIT
trap 'exit 143' TERM INT HUP

parent_alive() {
  local ppid
  ppid="$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')"
  [[ -n "$ppid" && "$ppid" != "1" ]]
}

# --- supervise -------------------------------------------------------------
backoff=2
while true; do
  # Run in the background and wait, so a TERM to the wrapper is handled at once
  # and the cleanup trap can stop the child.
  "$MON" "${args[@]}" &
  child=$!
  wait "$child"
  code=$?
  child=""
  if ! parent_alive; then
    echo "[supervisor] dlb-monitor(${NAME}) parent gone; stopping"
    exit 0
  fi
  if (( code == EXIT_VERSION_CHANGED )); then
    echo "[supervisor] dlb-monitor(${NAME}) exited code=${code} (dlb-mcp upgraded); respawning now on the new version"
    backoff=2
    continue
  fi
  echo "[supervisor] dlb-monitor(${NAME}) exited code=${code}; respawning in ${backoff}s"
  sleep "$backoff"
  if (( backoff < 30 )); then backoff=$(( backoff * 2 )); fi
done
