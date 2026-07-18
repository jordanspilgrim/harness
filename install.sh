#!/usr/bin/env bash
# Install the agent harness into ~/.claude by symlinking agents/, commands/, hooks/.
#
# Claude Code merges global ~/.claude/{agents,commands,hooks} into EVERY project, so after this
# runs, every repo — existing or brand-new — inherits the roster, the /kickoff · /standup ·
# /promote · /harness-init commands, and the DLB/branch hooks with zero per-project files. What
# differs per project lives in that repo's committed .claude/project.md (see schema/project.md).
#
# Symlinks (not copies) so edits in this repo are live everywhere and nothing drifts. Idempotent.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude"

link_dir() { # link_dir <srcdir> <destdir> <glob>
  local src="$1" dest="$2" glob="$3" f
  mkdir -p "$dest"
  for f in "$src"/$glob; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "$dest/$(basename "$f")"
    echo "  $dest/$(basename "$f") -> $f"
  done
}

echo "Installing harness: $REPO -> $DEST"
link_dir "$REPO/agents"            "$DEST/agents"            "*.md"
link_dir "$REPO/agents/_templates" "$DEST/agents/_templates" "*"
link_dir "$REPO/commands"          "$DEST/commands"          "*.md"
link_dir "$REPO/hooks"             "$DEST/hooks"             "*.sh"

cat <<'EOF'

Done. Roster + commands + hooks now resolve globally in every repo.

One-time wiring (only if not already present) — add dlb-autoregister to the SessionStart array in
~/.claude/settings.json so role threads auto-register/title on spawn in ANY project:

  {
    "matcher": "*",
    "hooks": [
      { "type": "command", "command": "bash ~/.claude/hooks/dlb-autoregister.sh SessionStart # dlb-autoregister" }
    ]
  }

Notes:
- dlb-monitor-supervised.sh is launched via the Monitor tool (not a settings hook).
- block-branch-switch.sh is wired PER-PROJECT (only when a repo's .claude/project.md has
  worktree_isolation: true) — /harness-init adds that wiring. It is NOT wired globally, so simple
  single-branch repos are never blocked from normal branch switches.
- Each repo needs a .claude/project.md — run /harness-init in a new repo to scaffold one.
EOF
