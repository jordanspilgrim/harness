#!/usr/bin/env bash
# SessionStart hook — auto-register a role thread on DLB with a unique identity.
#
# How a thread declares its role (first match wins):
#   1. env  DLB_ROLE=<token>            (set when launching the worktree/terminal)
#   2. file .claude/.dlb-role           (one token, written by pjm/launcher per worktree)
# A session with no role configured is a normal session — this hook does nothing.
#
# Tokens: ideator designer architect pjm fe-dev be-dev reviewer qa uat deployer bugfixer documenter
#
# Naming: singleton roles register under their canonical token (only one active at a time).
# Scalable roles (fe-dev, be-dev) get a unique suffix so many can run at once. Override the
# whole name with DLB_NAME=... , or force a suffix on any role with DLB_INSTANCE=... .
set -euo pipefail

input=$(cat 2>/dev/null || true)   # drain SessionStart payload (unused)

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
ROLE="${DLB_ROLE:-}"
[ -z "$ROLE" ] && [ -f "$PROJ/.claude/.dlb-role" ] && ROLE="$(tr -d '[:space:]' < "$PROJ/.claude/.dlb-role")"
[ -z "$ROLE" ] && exit 0   # not a role thread → no-op

# token → card filename
case "$ROLE" in
  ideator)   CARD="ideator.md" ;;
  designer)  CARD="designer.md" ;;
  architect) CARD="architect.md" ;;
  pjm)       CARD="program-manager.md" ;;
  fe-dev)    CARD="frontend-dev.md" ;;
  be-dev)    CARD="backend-dev.md" ;;
  reviewer)  CARD="code-reviewer.md" ;;
  qa)        CARD="qa-tester.md" ;;
  uat)       CARD="uat-tester.md" ;;
  deployer)  CARD="deployment-manager.md" ;;
  bugfixer)  CARD="bug-fixer.md" ;;
  documenter) CARD="documenter.md" ;;
  *) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"DLB autoregister: unknown role token '$ROLE' — fix .claude/.dlb-role or \$DLB_ROLE.\"}}"; exit 0 ;;
esac

# Compute the DLB name.
NAME="${DLB_NAME:-}"
if [ -z "$NAME" ]; then
  UID6="$(printf '%s' "${PROJ}:${ROLE}:$$" | shasum 2>/dev/null | cut -c1-6)"
  case "$ROLE" in
    fe-dev|be-dev) NAME="${ROLE}-${DLB_INSTANCE:-$UID6}" ;;             # scalable → unique
    *)             NAME="${ROLE}${DLB_INSTANCE:+-$DLB_INSTANCE}" ;;      # singleton → canonical
  esac
fi

CTX="AGENT ROLE BOOTSTRAP — You are the '${ROLE}' for this thread; your DLB identity is '${NAME}'. \
FIRST, before anything else: (1) mcp__dlb__register(name=\"${NAME}\", working_on=\"<feature>\", force=true) and store the session_token \
(force=true reclaims your name if a stale prior session held it — 30-min takeover window); \
(2) set your model tier with /model per the table in ~/.claude/agents/README.md; \
(3) Monitor({command: \"~/.claude/hooks/dlb-monitor-supervised.sh --name ${NAME}\", persistent: true}) — the supervised wrapper respawns the monitor if it exits; \
(4) read ~/.claude/agents/${CARD} and ~/.claude/agents/README.md, load the memory/ topic files matching your task, then .claude/plans/<feature>/manifest.md. \
Then follow the DLB Inbox Protocol. Report your registered name to pjm so it is recorded in the manifest roster."

# Title this session with its fleet identity so it's recognizable at a glance in
# the session list: "<role> (<dlb-name>)", collapsing to just the name when a
# singleton's role == name (e.g. "pjm" not "pjm (pjm)"). SessionStart hooks set
# the title via hookSpecificOutput.sessionTitle (Claude Code 2.1.x+); ignored by
# older versions, so it's safe to always emit.
if [ "$ROLE" = "$NAME" ]; then TITLE="$NAME"; else TITLE="$ROLE ($NAME)"; fi

# Emit as SessionStart additionalContext + sessionTitle (JSON-escaped).
printf '%s' "$CTX" | TITLE="$TITLE" python3 -c 'import json,sys,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.stdin.read(),"sessionTitle":os.environ["TITLE"]}}))'
