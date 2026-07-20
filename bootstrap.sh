#!/usr/bin/env bash
# Refresh this harness checkout to latest and (re)install into ~/.claude.
# Run from a harness clone. For a project that may not have the harness yet, use the
# self-contained project bootstrap instead (templates/project-bootstrap.sh — what
# /harness-init drops into each repo as scripts/harness-bootstrap.sh).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" pull --ff-only 2>/dev/null || echo "harness: could not fast-forward (local changes?) — installing current checkout"
fi
exec "$REPO/install.sh"
