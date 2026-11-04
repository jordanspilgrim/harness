#!/usr/bin/env bash
# Regression test for dlb-access-check.sh.
# Run:  bash ~/.claude/hooks/dlb-access-check.test.sh
#
# Like dlb-autoregister.sh, this hook can be wired globally and ~/.claude/hooks symlinks into the
# harness working tree, so a broken edit breaks session start everywhere. Every case asserts exit 0
# and valid JSON on top of the behaviour under test, and each "fires" case is paired with the
# benign neighbour it must stay silent on.
#
# HOME is a temp dir in every case, so the real ~/.claude.json is never read.
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")" && pwd)/dlb-access-check.sh}"
TMP=$(mktemp -d); trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME"
pass=0; fail=0

mkproj() { # mkproj <dirname> <role|-> ; descriptor yaml body on stdin
  local d="$TMP/$1"; mkdir -p "$d/.claude"
  { printf '# desc\n\n```yaml\nname: %s\nstack: "x"\n' "$1"; cat; printf '```\n'; } > "$d/.claude/project.md"
  [ "$2" != "-" ] && printf '%s\n' "$2" > "$d/.claude/.dlb-role"
  printf '%s' "$d"
}

run() { # run <label> <NONE|substring|!substring> <env-assignments...> -- <projdir>
  local label="$1" expect="$2"; shift 2
  local env=(); while [ "$1" != "--" ]; do env+=("$1"); shift; done; shift
  local proj="$1" out rc
  out=$(env -i PATH="$PATH" HOME="$FAKEHOME" CLAUDE_PROJECT_DIR="$proj" \
        ${env[@]+"${env[@]}"} bash "$HOOK" </dev/null 2>&1); rc=$?

  local why=""
  [ $rc -ne 0 ] && why="nonzero exit ($rc)"
  if [ -z "$why" ] && [ -n "$out" ]; then
    printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || why="invalid JSON"
  fi
  if [ -z "$why" ]; then
    case "$expect" in
      NONE) [ -n "$out" ] && why="expected silence, got output" ;;
      !*)   [ -z "$out" ] && why="expected output, got silence"
            printf '%s' "$out" | grep -q -- "${expect#!}" && why="should NOT contain '${expect#!}'" ;;
      *)    printf '%s' "$out" | grep -q -- "$expect" || why="missing '$expect'" ;;
    esac
  fi

  if [ -z "$why" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  %-46s %s\n' "$label" "$why"
    [ -n "$out" ] && printf '      got: %.200s\n' "$(printf '%s' "$out" | tr '\n' ' ')"
  fi
}

mkdir -p "$TMP/specs" "$TMP/locked"; chmod 000 "$TMP/locked"

# --- no-ops ---------------------------------------------------------------------------------
NOROLE=$(mkproj norole - <<'Y'
access:
  be-dev:
    tools: [definitely-not-a-real-tool-xyz]
Y
)
run "no role -> silent"                        NONE -- "$NOROLE"
mkdir -p "$TMP/nodesc/.claude"; echo be-dev > "$TMP/nodesc/.claude/.dlb-role"
run "no descriptor -> silent"                  NONE -- "$TMP/nodesc"

NONE_P=$(mkproj accnone be-dev <<'Y'
access: none
Y
)
run "access: none -> silent"                   NONE -- "$NONE_P"

NOKEY=$(mkproj nokey be-dev <<'Y'
roster_profile: small
Y
)
run "no access key -> silent"                  NONE -- "$NOKEY"

ABSENT=$(mkproj absent pjm <<'Y'
access:
  be-dev:
    tools: [definitely-not-a-real-tool-xyz]
Y
)
run "role absent from map -> silent"           NONE -- "$ABSENT"

# --- tools ----------------------------------------------------------------------------------
TOOL_OK=$(mkproj toolok be-dev <<'Y'
access:
  be-dev:
    tools: [sh, python3]
Y
)
run "present tools -> silent"                  NONE -- "$TOOL_OK"
TOOL_BAD=$(mkproj toolbad be-dev <<'Y'
access:
  be-dev:
    tools: [sh, definitely-not-a-real-tool-xyz]
Y
)
run "missing tool -> MISSING ACCESS"           "definitely-not-a-real-tool-xyz" -- "$TOOL_BAD"
run "missing tool -> blocked rule"             'set_status' -- "$TOOL_BAD"
run "missing tool -> present tool not listed"  '!tool `sh`' -- "$TOOL_BAD"

# --- paths ----------------------------------------------------------------------------------
PATH_OK=$(mkproj pathok be-dev <<Y
access:
  be-dev:
    paths: [$TMP/specs, .claude]
Y
)
run "existing abs + relative path -> silent"   NONE -- "$PATH_OK"
PATH_BAD=$(mkproj pathbad be-dev <<Y
access:
  be-dev:
    paths: [$TMP/specs, $TMP/nope]
Y
)
run "missing path -> does not exist"           "does not exist" -- "$PATH_BAD"
run "missing path -> good path not listed"     "!$TMP/specs\` does" -- "$PATH_BAD"
if [ "$(id -u)" -ne 0 ]; then
  PATH_LOCK=$(mkproj pathlock be-dev <<Y
access:
  be-dev:
    paths: [$TMP/locked]
Y
)
  run "unreadable path -> not readable"        "not readable" -- "$PATH_LOCK"
fi
mkdir -p "$FAKEHOME/docs"
TILDE=$(mkproj tilde be-dev <<'Y'
access:
  be-dev:
    paths: [~/docs]
Y
)
run "~ path expands against HOME -> silent"    NONE -- "$TILDE"

# --- mcp ------------------------------------------------------------------------------------
MCP_P=$(mkproj mcp product-lead <<'Y'
access:
  product-lead:
    mcp: [Notion, slack]
Y
)
printf '{"mcpServers":{"notion":{"command":"x"},"slack":{"command":"y"}}}' > "$MCP_P/.mcp.json"
run "mcp in .mcp.json (case-insensitive)"      NONE -- "$MCP_P"
rm "$MCP_P/.mcp.json"
run "mcp not found -> unverified"              "not found in local config" -- "$MCP_P"
run "mcp not found -> not a hard gap"          '!MISSING ACCESS' -- "$MCP_P"
REAL=$(cd "$MCP_P" && pwd -P)
printf '{"mcpServers":{"notion":{}},"projects":{"%s":{"mcpServers":{"slack":{}}}}}' "$REAL" > "$FAKEHOME/.claude.json"
run "mcp in ~/.claude.json user+project"       NONE -- "$MCP_P"
printf '{"projects":{"/some/other/repo":{"mcpServers":{"slack":{}}}},"mcpServers":{"notion":{}}}' > "$FAKEHOME/.claude.json"
run "other project's server does not count"    "slack" -- "$MCP_P"
rm -f "$FAKEHOME/.claude.json"

# --- list forms + comments ------------------------------------------------------------------
BLOCK=$(mkproj block be-dev <<'Y'
access:   # role -> needs
  pjm:
    tools: [definitely-not-a-real-tool-xyz]
  be-dev:
    tools:
      - sh          # always there
      - "definitely-not-a-real-tool-abc"
    paths:
      - .claude
other_key: value
Y
)
run "block list -> parses quoted item"         "definitely-not-a-real-tool-abc" -- "$BLOCK"
run "block list -> other role ignored"         '!definitely-not-a-real-tool-xyz' -- "$BLOCK"
SCALAR=$(mkproj scalar be-dev <<'Y'
access:
  be-dev:
    tools: sh
Y
)
run "scalar value -> silent"                   NONE -- "$SCALAR"

# --- malformed ------------------------------------------------------------------------------
BADINLINE=$(mkproj badinline be-dev <<'Y'
access: [be-dev]
Y
)
run "inline non-map access -> NOT verified"    "NOT verified" -- "$BADINLINE"
BADLIST=$(mkproj badlist be-dev <<'Y'
access:
  be-dev:
    tools: [sh, python3
Y
)
run "unterminated list -> NOT verified"        "NOT verified" -- "$BADLIST"
BADKEY=$(mkproj badkey be-dev <<'Y'
access:
  be-dev:
    tool: [sh]
Y
)
run "unknown key -> NOT verified"              "unknown key" -- "$BADKEY"

# --- role resolution ------------------------------------------------------------------------
run "DLB_ROLE overrides marker (pjm absent)"   NONE DLB_ROLE=pjm -- "$TOOL_BAD"
run "DLB_ROLE selects a role with a gap"       "MISSING ACCESS" DLB_ROLE=be-dev -- "$NOROLE"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
