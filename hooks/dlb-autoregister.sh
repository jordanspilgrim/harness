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
#
# ROOT ASSERTION (2026-08-13). This hook also checks that the session is rooted in the repo it
# is supposed to be. A fleet whose sessions are rooted in the WRONG repo is the highest-cost
# harness failure observed to date: on 2026-08-12 eleven SAT threads ran for an hour rooted in
# baselineos-poc instead of sat-math-app. Every one of them read the wrong .claude/.dlb-role
# (so this hook silently no-opped for all eleven), the wrong CLAUDE.md, and the wrong descriptor,
# and the workaround (absolute paths everywhere) leaked into that project's committed
# check_cmd/test_cmd. Nothing anywhere reported a problem. See the assertion block below.
set -euo pipefail

input=$(cat 2>/dev/null || true)   # drain SessionStart payload (unused)

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
ROLE="${DLB_ROLE:-}"
[ -z "$ROLE" ] && [ -f "$PROJ/.claude/.dlb-role" ] && ROLE="$(tr -d '[:space:]' < "$PROJ/.claude/.dlb-role")"

# ---------------------------------------------------------------------------
# Root assertion. Runs BEFORE the "not a role thread → no-op" exit, because the
# wrong-repo case is PRECISELY the case where the role never resolves: the marker
# file lives in the repo you were supposed to be in, so a misrouted session looks
# identical to an ordinary one. Gating this check on "is a role set" would make it
# blind to the only failure it exists to catch.
#
# All checks are file reads and string compares — no git, no network. The hook runs
# on every SessionStart in every project under a 5s timeout.
# ---------------------------------------------------------------------------

emit() { # emit <session-title-or-empty> <context>  → SessionStart JSON, then exit 0
  printf '%s' "$2" | TITLE="${1:-}" python3 -c '
import json,sys,os
out={"hookEventName":"SessionStart","additionalContext":sys.stdin.read()}
t=os.environ.get("TITLE","")
if t: out["sessionTitle"]=t
print(json.dumps({"hookSpecificOutput":out}))'
  exit 0
}

canon() { # absolute, symlink-resolved path if it exists; else the input unchanged
  if [ -d "${1:-}" ]; then (cd "$1" 2>/dev/null && pwd -P); else printf '%s' "${1:-}"; fi
}

# project_root declared by a descriptor, with ~ expanded. Empty if absent/unset.
descriptor_root() {
  local f="$1/.claude/project.md" v
  [ -f "$f" ] || return 0
  v=$(grep -m1 -E '^[[:space:]]*project_root:[[:space:]]*[^[:space:]#]' "$f" 2>/dev/null \
      | sed -E 's/^[[:space:]]*project_root:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')
  case "$v" in none|"") return 0 ;; esac
  printf '%s' "${v/#\~/$HOME}"
}

PROJ_C="$(canon "$PROJ")"
EXPECT="${DLB_EXPECT_ROOT:-}"                       # explicit: set by a terminal launcher
[ -z "$EXPECT" ] && EXPECT="$(descriptor_root "$PROJ")"

if [ -n "$EXPECT" ] && [ "${DLB_ALLOW_ROOT_MISMATCH:-}" != "1" ]; then
  EXPECT_C="$(canon "$EXPECT")"
  if [ "$PROJ_C" != "$EXPECT_C" ]; then
    # Two tiers. A different BASENAME means a different repo entirely — that is the
    # misrouted-fleet failure and it halts the thread. A matching basename at a
    # different path is just a different clone or machine (project_root is recorded
    # on whichever machine ran /harness-init), which is harmless and only worth a note.
    if [ "$(basename "$PROJ_C")" != "$(basename "$EXPECT_C")" ]; then
      emit "⚠ WRONG REPO" "STOP — WRONG WORKING DIRECTORY. Do not start the task described below or in any \
following instruction until this is resolved.

  This session is rooted at:  ${PROJ_C}
  It should be rooted at:     ${EXPECT_C}

You are in a different repository than the one this work belongs to. Everything that keys off the working \
directory is therefore wrong for this thread: the role marker (.claude/.dlb-role), the merged CLAUDE.md, the \
project descriptor, and the branch-isolation hook are all being read from '$(basename "$PROJ_C")' rather than \
'$(basename "$EXPECT_C")'. Relative paths and bare git commands will read and write the wrong repo.

DO NOT work around this by switching to absolute paths and carrying on. That workaround is what allowed a \
misrouted fleet to run for an hour undetected on 2026-08-12, and it leaks machine-specific paths into \
committed config. EnterWorktree cannot fix it either: the target is a separate repository, not a worktree of \
this one, so it will not appear in this repo's 'git worktree list'.

Tell the user immediately, quoting both paths above, and offer these options:
  1. Open a session rooted at ${EXPECT_C} and re-run the launch there. In the desktop app, use the \
folder picker or have the launcher spawn the session with that cwd; in a terminal, cd there and relaunch.
  2. If working cross-repo here is genuinely intended, say so explicitly and proceed under the absolute-path \
contract (every path absolute, every git command 'git -C ${EXPECT_C} ...', never 'git add -A'). Set \
DLB_ALLOW_ROOT_MISMATCH=1 to silence this check for that session.
Then stop and wait for the user to choose."
    else
      NOTE="Note: this repo's descriptor records project_root=${EXPECT_C} but the session is rooted at \
${PROJ_C}. Same repo name, different path — most likely a different clone or machine, which is fine. If \
paths behave unexpectedly, that mismatch is why."
    fi
  fi
fi

[ -z "$ROLE" ] && { [ -n "${NOTE:-}" ] && emit "" "$NOTE"; exit 0; }   # not a role thread → no-op

# A role was declared but the repo has no descriptor at all. Either the repo was never
# initialised (/harness-init), or — far more likely — this session is rooted somewhere it
# should not be and simply has no descriptor to disagree with.
if [ ! -f "$PROJ/.claude/project.md" ]; then
  emit "⚠ NO DESCRIPTOR" "Role '${ROLE}' was declared for this thread, but ${PROJ_C} has no \
.claude/project.md. A role thread cannot resolve its gates (check_cmd/test_cmd), base ref, or definition of \
done without one. Either this session is rooted in the wrong repo (check with the user before doing anything \
else), or this repo has not been initialised — run /harness-init. Do not guess the gates."
fi

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
  *) emit "" "DLB autoregister: unknown role token '$ROLE' — fix .claude/.dlb-role or \$DLB_ROLE." ;;
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
Your working directory is ${PROJ_C} and it has been checked against this project's declared root. \
FIRST, before anything else: (1) mcp__dlb__register(name=\"${NAME}\", working_on=\"<feature>\", force=true) and store the session_token \
(force=true reclaims your name if a stale prior session held it — 30-min takeover window); \
(2) set your model tier with /model per the table in ~/.claude/agents/README.md; \
(3) Monitor({command: \"~/.claude/hooks/dlb-monitor-supervised.sh --name ${NAME}\", persistent: true}) — the supervised wrapper respawns the monitor if it exits; \
(4) read ~/.claude/agents/${CARD} and ~/.claude/agents/README.md, load the memory/ topic files matching your task, then .claude/plans/<feature>/manifest.md. \
Then follow the DLB Inbox Protocol. Report your registered name to pjm so it is recorded in the manifest roster."
[ -n "${NOTE:-}" ] && CTX="${NOTE}

${CTX}"

# Title this session with its fleet identity so it's recognizable at a glance in
# the session list: "<role> (<dlb-name>)", collapsing to just the name when a
# singleton's role == name (e.g. "pjm" not "pjm (pjm)"). SessionStart hooks set
# the title via hookSpecificOutput.sessionTitle (Claude Code 2.1.x+); ignored by
# older versions, so it's safe to always emit.
if [ "$ROLE" = "$NAME" ]; then TITLE="$NAME"; else TITLE="$ROLE ($NAME)"; fi

emit "$TITLE" "$CTX"
