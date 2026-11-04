#!/usr/bin/env bash
# SessionStart hook (OPTIONAL) — check this role thread's declared access outside /kickoff.
#
# /kickoff checks every role's `access:` entry before launch. This hook repeats that check for
# ONE role whenever its session starts, resumes, or compacts, so a gap that appears later (a
# connector removed, a tool uninstalled, a path unmounted) surfaces at the next session boundary
# instead of being routed around mid-task. See schema/project.md, "access".
#
# Role resolution matches dlb-autoregister.sh: env DLB_ROLE, else .claude/.dlb-role. A session
# with no role, no descriptor, `access: none`, or no entry for its role is a no-op.
#
# Checks (all local, no network — this runs under a 5s timeout):
#   tools  — `command -v` on PATH
#   paths  — exists and is readable (~ expanded)
#   mcp    — server name present in ~/.claude.json (user + this project's entry) or
#            <project>/.mcp.json. claude.ai connectors are not visible offline; a name not
#            found locally is reported as unverified, with the command to confirm it.
#
# Silent when everything resolves. Always exits 0 and emits valid SessionStart JSON.
set -euo pipefail

cat >/dev/null 2>&1 || true   # drain SessionStart payload (unused)

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
ROLE="${DLB_ROLE:-}"
[ -z "$ROLE" ] && [ -f "$PROJ/.claude/.dlb-role" ] && ROLE="$(tr -d '[:space:]' < "$PROJ/.claude/.dlb-role")"
[ -z "$ROLE" ] && exit 0
[ -f "$PROJ/.claude/project.md" ] || exit 0

PROJ="$PROJ" ROLE="$ROLE" python3 - <<'PY' || true
import json, os, re, shutil, sys

proj, role = os.environ["PROJ"], os.environ["ROLE"]
home = os.path.expanduser("~")

def emit(ctx):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": ctx}}))
    sys.exit(0)

try:
    text = open(os.path.join(proj, ".claude", "project.md"), encoding="utf-8").read()
except OSError:
    sys.exit(0)

# Only the first ```yaml fence is the descriptor.
m = re.search(r"```ya?ml\s*\n(.*?)```", text, re.S)
if not m:
    sys.exit(0)
lines = m.group(1).splitlines()

def strip_comment(s):
    out, q = [], None
    for ch in s:
        if q:
            if ch == q: q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#":
            break
        out.append(ch)
    return "".join(out).rstrip()

def unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s

def indent(s):
    return len(s) - len(s.lstrip(" "))

# Locate the top-level `access:` key.
start = None
for i, raw in enumerate(lines):
    l = strip_comment(raw)
    mm = re.match(r"^access:\s*(.*)$", l)
    if mm:
        inline = mm.group(1).strip()
        if inline in ("none", "", "~", "null", "{}"):
            if inline != "":
                sys.exit(0)          # access: none -> check disabled
        else:
            emit(f"DLB access check: could not read `access:` in .claude/project.md "
                 f"(inline value {inline!r}). Use `none` or a block map of role -> "
                 f"{{mcp, tools, paths}}. Access for role '{role}' was NOT verified.")
        start = i + 1
        break
if start is None:
    sys.exit(0)

# Collect the access block: every following line indented deeper than column 0.
block = []
for raw in lines[start:]:
    l = strip_comment(raw)
    if not l.strip():
        continue
    if indent(l) == 0:
        break
    block.append(l)
if not block:
    sys.exit(0)

def parse_list(val, rest):
    """Inline [a, b] / bare scalar, or a following block of `- item` lines."""
    val = val.strip()
    if val.startswith("["):
        if not val.endswith("]"):
            raise ValueError(f"unterminated list {val!r}")
        return [unquote(x) for x in val[1:-1].split(",") if x.strip()]
    if val:
        return [unquote(val)]
    items = []
    for l in rest:
        mm = re.match(r"^\s*-\s*(.+)$", l)
        if not mm:
            break
        items.append(unquote(mm.group(1)))
    return items

try:
    role_ind = indent(block[0])
    entry, found = None, False
    for j, l in enumerate(block):
        if indent(l) != role_ind:
            continue
        mm = re.match(r"^\s*([^:\s][^:]*):\s*(.*)$", l)
        if not mm:
            raise ValueError(f"unexpected line {l.strip()!r}")
        if unquote(mm.group(1)) != role:
            continue
        found = True
        inline = mm.group(2).strip()
        if inline in ("none", "{}", "~", "null"):
            entry = {}
            break
        if inline:
            raise ValueError(f"role '{role}' has inline value {inline!r}; expected a map")
        body = []
        for k in block[j + 1:]:
            if indent(k) <= role_ind:
                break
            body.append(k)
        entry = {}
        for n, k in enumerate(body):
            km = re.match(r"^\s*(mcp|tools|paths):\s*(.*)$", k)
            if km:
                entry[km.group(1)] = parse_list(km.group(2), body[n + 1:])
            elif not re.match(r"^\s*-\s", k):
                raise ValueError(f"unknown key in '{role}': {k.strip()!r} "
                                 f"(expected mcp, tools, paths)")
        break
except ValueError as e:
    emit(f"DLB access check: could not parse `access:` in .claude/project.md ({e}). "
         f"Access for role '{role}' was NOT verified; fix the descriptor or run /kickoff's check.")

if not found or not entry:
    sys.exit(0)                      # role absent from the map -> needs nothing beyond the repo

gaps, unverified = [], []

for t in entry.get("tools", []):
    if not shutil.which(t):
        gaps.append(f"tool `{t}` not found on PATH")

for p in entry.get("paths", []):
    full = os.path.expanduser(p)
    if not os.path.isabs(full):
        full = os.path.join(proj, full)
    if not os.path.exists(full):
        gaps.append(f"path `{p}` does not exist")
    elif not os.access(full, os.R_OK):
        gaps.append(f"path `{p}` is not readable")

wanted = entry.get("mcp", [])
if wanted:
    names = set()
    def add_servers(d):
        if isinstance(d, dict):
            names.update(k.lower() for k in d)
    try:
        cfg = json.load(open(os.path.join(home, ".claude.json"), encoding="utf-8"))
        add_servers(cfg.get("mcpServers"))
        projects = cfg.get("projects") or {}
        real = os.path.realpath(proj)
        for key, val in projects.items():
            if os.path.realpath(key) == real and isinstance(val, dict):
                add_servers(val.get("mcpServers"))
    except (OSError, ValueError):
        pass
    try:
        add_servers(json.load(open(os.path.join(proj, ".mcp.json"), encoding="utf-8"))
                    .get("mcpServers"))
    except (OSError, ValueError, AttributeError):
        pass
    for s in wanted:
        if s.lower() not in names:
            unverified.append(s)

if not gaps and not unverified:
    sys.exit(0)

msg = [f"DLB access check for role '{role}' (from .claude/project.md `access:`):"]
if gaps:
    msg.append("MISSING ACCESS:")
    msg += [f"  - {g}" for g in gaps]
if unverified:
    msg.append("MCP servers not found in local config (~/.claude.json, .mcp.json): "
               + ", ".join(f"`{s}`" for s in unverified)
               + ". A claude.ai connector is not visible offline: run `/mcp` or "
                 "`claude mcp list` to confirm before relying on it.")
msg.append("Rule: if any access you need is missing, do not start that work and do NOT ask "
           "another agent to do it for you. Call set_status(name, token, \"blocked\", "
           "detail=\"missing access: <what>\"), tell the owner exactly what to add, and tell "
           "pjm so it lands in the manifest's Access table.")
emit("\n".join(msg))
PY
exit 0
