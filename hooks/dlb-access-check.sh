#!/usr/bin/env bash
# SessionStart hook (OPTIONAL): re-check this role thread's declared access at every session start.
#
# /kickoff checks every role's `access:` entry once, before launch. This hook repeats the check for
# ONE role whenever its session starts, resumes, or compacts, so a gap that appears later (a tool
# uninstalled, a path unmounted, an MCP server removed from config) surfaces at the next session
# boundary instead of being routed around mid-task. See schema/project.md, "access".
#
# Descriptor: the nearest .claude/project.md at or above CLAUDE_PROJECT_DIR (else $PWD). The walk
# stops at the first directory holding .git and never uses $HOME's own .claude/project.md. Only
# the first ```yaml fence is read; a second fence gets a note saying so.
#
# Role: env DLB_ROLE, else .claude/.dlb-role in the session dir, else in the descriptor's dir.
# No role, no descriptor, `access: none`, or no entry for the role is a silent no-op. Map keys
# must be DLB role tokens; an unknown key gets a non-blocking note.
#
# Checks (local only, no network; wire it with a 5s timeout):
#   tools       found by `command -v` on this session's PATH. On a miss, a few common install dirs
#               are searched too; a hit there is a note ("not on this session's PATH"), not a gap.
#   paths       exist and are readable, after ~ and $VAR expansion. A relative path resolves
#               against the project root: the directory that holds .claude/project.md.
#   mcp         the server name is a configured key under mcpServers in ~/.claude.json (user
#               scope, or the projects entry for the session or project dir) or in .mcp.json.
#               A name that is not configured is a note, not a gap: config keys say nothing about
#               whether a server is connected, and claude.ai connectors live in no local file.
#   connectors  claude.ai connectors. Skipped here; /kickoff verifies them.
#
# Output: silent when there is nothing to say. Hard gaps (a tool missing everywhere, a path
# missing or unreadable) inject the blocked rule. Notes alone inject one line each and no rule.
# A descriptor this hook cannot parse, or any internal error, yields "access NOT verified:
# <reason>". Descriptor text is echoed only after an allowlist filter and a length cap.
#
# Contract: ALWAYS exits 0 and prints either nothing or one valid SessionStart JSON object.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain SessionStart payload (unused)

fallback() { # fallback <reason>: fixed JSON, needs no python
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"DLB access check: access NOT verified: %s."}}\n' "$1"
}

START="${CLAUDE_PROJECT_DIR:-$PWD}"

if ! command -v python3 >/dev/null 2>&1; then
  # Stay silent unless this looks like a role thread; otherwise every session carries the note.
  if [ -n "${DLB_ROLE:-}" ] || [ -e "$START/.claude/.dlb-role" ]; then
    fallback "python3 is not on this session's PATH, so the checker could not run"
  fi
  exit 0
fi

# The checker is read into a variable rather than fed as a heredoc inside $(...): bash 3.2
# (macOS /bin/bash) mis-parses quotes and parentheses in a heredoc inside command substitution.
PYSRC=""
IFS= read -r -d '' PYSRC <<'PY' || true
import json, os, re, shutil, sys

KNOWN_ROLES = ("ideator", "designer", "architect", "pjm", "fe-dev", "be-dev", "reviewer", "qa",
               "uat", "deployer", "bugfixer", "documenter")
ENTRY_KEYS = ("mcp", "tools", "paths", "connectors")
SHIM_DIRS = ("/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.cargo/bin")
SAFE_CH = re.compile(r"[A-Za-z0-9 _.,:/~@+=$%-]")
MAX_ITEM = 80
MAX_CTX = 4000

def safe(v, cap=MAX_ITEM):
    """Render descriptor-derived text for the model: allowlisted chars, capped, repr-quoted."""
    s = "".join(c if SAFE_CH.fullmatch(c) else "?" for c in str(v))
    if len(s) > cap:
        s = s[:cap] + "..."
    return repr(s)

def emit(ctx):
    if len(ctx) > MAX_CTX:
        ctx = ctx[:MAX_CTX] + "\n[truncated]"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": ctx}}))
    sys.exit(0)

def not_verified(reason, role=None):
    who = f" for role {safe(role)}" if role else ""
    emit(f"DLB access check: access{who} NOT verified: {reason}. Fix .claude/project.md "
         f"(see schema/project.md, \"access\") or run /kickoff's access check by hand.")

class ParseError(Exception):
    pass

# ---- a small YAML-subset parser: block maps/lists, flow [..] and {..}, quoted scalars ----------

EMPTY = object()   # "no inline value" (a block may follow)
NULLS = ("~", "null", "Null", "NULL")

class Cur:
    def __init__(self, s):
        self.s, self.i = s, 0
    def peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""
    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t":
            self.i += 1
    def at_end(self):
        """End of line, or a comment (# at the start or after whitespace)."""
        if self.i >= len(self.s):
            return True
        return self.s[self.i] == "#" and (self.i == 0 or self.s[self.i - 1] in " \t")

    def quoted(self):
        q = self.s[self.i]; self.i += 1; out = []
        while self.i < len(self.s):
            c = self.s[self.i]
            if q == "'" and c == "'":
                if self.s[self.i + 1:self.i + 2] == "'":
                    out.append("'"); self.i += 2; continue
                self.i += 1; return "".join(out)
            if q == '"' and c == "\\" and self.i + 1 < len(self.s):
                n = self.s[self.i + 1]
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, n)); self.i += 2
                continue
            if q == '"' and c == '"':
                self.i += 1; return "".join(out)
            out.append(c); self.i += 1
        raise ParseError("unterminated quoted string")

    def plain(self, flow, key=False):
        st = self.i
        while self.i < len(self.s):
            c = self.s[self.i]
            if c == "#" and self.i > st and self.s[self.i - 1] in " \t":
                break
            if flow and c in ",[]{}":
                break
            if c == ":" and (self.i + 1 >= len(self.s) or self.s[self.i + 1] in " \t,]}"):
                if key or flow:
                    break
                raise ParseError("a ': ' inside a plain value (quote it)")
            self.i += 1
        v = self.s[st:self.i].rstrip()
        if not v:
            raise ParseError("empty value")
        return v

    def value(self, flow):
        c = self.peek()
        if c == "[":
            return self.flow_list()
        if c == "{":
            return self.flow_map()
        if c in "\"'":
            return self.quoted()
        v = self.plain(flow)
        return None if v in NULLS else v

    def flow_list(self):
        self.i += 1; out = []
        while True:
            self.ws()
            if self.peek() == "]":
                self.i += 1; return out
            if not self.peek():
                raise ParseError("unterminated [...] list")
            out.append(self.value(flow=True))
            self.ws()
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c == "]":
                self.i += 1; return out
            else:
                raise ParseError("unterminated [...] list" if not c
                                 else "unexpected text inside a [...] list")

    def flow_map(self):
        self.i += 1; out = {}
        while True:
            self.ws()
            if self.peek() == "}":
                self.i += 1; return out
            if not self.peek():
                raise ParseError("unterminated {...} map")
            k = self.quoted() if self.peek() in "\"'" else self.plain(flow=True, key=True)
            self.ws()
            if self.peek() != ":":
                raise ParseError("expected ':' in a {...} map")
            self.i += 1; self.ws()
            out[k] = None if self.peek() in (",", "}") else self.value(flow=True)
            self.ws()
            c = self.peek()
            if c == ",":
                self.i += 1
            elif c == "}":
                self.i += 1; return out
            else:
                raise ParseError("unterminated {...} map" if not c
                                 else "unexpected text inside a {...} map")

def inline(s):
    c = Cur(s); c.ws()
    if c.at_end():
        return EMPTY
    v = c.value(flow=False)
    c.ws()
    if not c.at_end():
        raise ParseError("unexpected text after a value")
    return v

def split_key(content):
    """'key: rest' -> (key, rest); None if the line is not a map entry."""
    c = Cur(content)
    if c.peek() in "\"'":
        try:
            k = c.quoted()
        except ParseError:
            return None
        c.ws()
    else:
        try:
            k = c.plain(flow=False, key=True)
        except ParseError:
            return None
    if c.peek() != ":":
        return None
    return k, content[c.i + 1:]

def is_item(content):
    return content == "-" or content.startswith("- ")

def parse_block(lines, i, ind):
    if is_item(lines[i][1]):
        return parse_seq(lines, i, ind)
    return parse_map(lines, i, ind)

def child(lines, i, ind, allow_indentless_seq):
    """Value for an entry whose inline part was empty: a deeper block, or None."""
    if i < len(lines):
        nind, ncont = lines[i]
        if nind > ind or (allow_indentless_seq and nind == ind and is_item(ncont)):
            return parse_block(lines, i, nind)
    return None, i

def parse_map(lines, i, ind):
    out = {}
    while i < len(lines):
        lind, cont = lines[i]
        if lind < ind:
            break
        if lind > ind:
            raise ParseError("unexpected indentation")
        if is_item(cont):
            raise ParseError("a list item where a key was expected")
        kv = split_key(cont)
        if kv is None:
            raise ParseError(f"expected 'key: value', got {safe(cont)}")
        k, rest = kv
        v = inline(rest)
        i += 1
        if v is EMPTY:
            v, i = child(lines, i, ind, allow_indentless_seq=True)
        out[k] = v
    return out, i

def parse_seq(lines, i, ind):
    out = []
    while i < len(lines):
        lind, cont = lines[i]
        if lind < ind or (lind == ind and not is_item(cont)):
            break
        if lind > ind:
            raise ParseError("unexpected indentation")
        rest = cont[1:]
        r = rest.strip()
        if r and r[0] not in "[{'\"" and split_key(r) is not None:
            raise ParseError("a 'key: value' list item is not supported here")
        v = inline(rest)
        i += 1
        if v is EMPTY:
            v, i = child(lines, i, ind, allow_indentless_seq=False)
        out.append(v)
    return out, i

# ---- helpers -----------------------------------------------------------------------------------

home = os.path.expanduser("~")

def tilde(p):
    return "~" + p[len(home):] if home and p.startswith(home) else p

def read_text(p):
    with open(p, "rb") as f:
        return f.read().decode("utf-8", errors="replace")

def find_descriptor_dir(start):
    d = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(d, ".claude", "project.md")) and \
                os.path.realpath(d) != os.path.realpath(home):
            return d
        if os.path.exists(os.path.join(d, ".git")):
            return None                 # repo root reached: never borrow a parent's descriptor
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent

def as_list(v, where):
    if v is None or v == "none":
        return []
    if isinstance(v, list):
        out = []
        for x in v:
            if x is None:
                continue                # an empty `-` item
            if isinstance(x, (dict, list)):
                raise ParseError(f"{where} has a nested item; expected plain names")
            out.append(str(x))
        return out
    if isinstance(v, dict):
        raise ParseError(f"{where} is a map; expected a list")
    return [str(v)]

def load_json(p):
    """(dict-or-None, problem-or-None). Never raises on bad content."""
    try:
        data = json.loads(read_text(p))
    except FileNotFoundError:
        return None, None
    except (OSError, ValueError) as e:
        return None, f"could not read {tilde(p)} ({type(e).__name__})"
    if not isinstance(data, dict):
        return None, f"{tilde(p)} is not a JSON object"
    return data, None

def server_keys(d):
    return {str(k).lower() for k in d} if isinstance(d, dict) else set()

# ---- main --------------------------------------------------------------------------------------

def main():
    if os.environ.get("DLB_ACCESS_CHECK_FORCE_ERROR"):
        raise RuntimeError("forced by DLB_ACCESS_CHECK_FORCE_ERROR")
    start = os.environ.get("START") or os.getcwd()
    proj = find_descriptor_dir(start)
    if proj is None:
        return

    # Role: env, else the marker in the session dir, else in the descriptor dir.
    role = os.environ.get("DLB_ROLE", "").strip()
    if not role:
        for d in dict.fromkeys((start, proj)):
            marker = os.path.join(d, ".claude", ".dlb-role")
            if os.path.exists(marker):
                try:
                    role = "".join(read_text(marker).split())
                except OSError as e:
                    not_verified(f".claude/.dlb-role exists but could not be read "
                                 f"({type(e).__name__}), so the role is unknown")
                break
    if not role:
        return

    text = read_text(os.path.join(proj, ".claude", "project.md"))
    fences = re.findall(r"^```ya?ml[ \t]*\n(.*?)^```", text, re.S | re.M)
    if not fences:
        return
    notes = []
    if len(fences) > 1:
        notes.append(f"Note: .claude/project.md has {len(fences)} yaml fences; only the first "
                     f"is the descriptor, and it is the one checked.")
    lines = fences[0].split("\n")

    access_at = None
    for n, raw in enumerate(lines):
        if raw.startswith("access:"):
            access_at = n
            break

    def done():
        if notes:
            emit("\n".join(notes))
        sys.exit(0)

    if access_at is None:
        done()

    try:
        v = inline(lines[access_at][len("access:"):])
        body = []
        for raw in lines[access_at + 1:]:
            if not raw.strip():
                continue
            lead = raw[:len(raw) - len(raw.lstrip(" \t"))]
            if not lead:
                if raw.startswith("#"):
                    continue
                break                    # the next top-level key ends the block
            if "\t" in lead:
                raise ParseError("tab used for indentation (YAML allows spaces only)")
            content = raw[len(lead):]
            if content.startswith("#"):
                continue
            body.append((len(lead), content))
        if v is EMPTY:
            if body:
                v, used = parse_block(body, 0, body[0][0])
                if used != len(body):
                    raise ParseError("inconsistent indentation")
            else:
                v = None
        elif body:
            raise ParseError("`access:` has both an inline value and an indented block")
        if v is None or v == "none" or v == {}:
            done()
        if not isinstance(v, dict):
            raise ParseError("`access:` must be `none` or a map of role token to "
                             "{mcp, tools, paths, connectors}")
        access = v

        unknown = [k for k in access if str(k) not in KNOWN_ROLES]
        if unknown:
            notes.append("Note: `access:` has keys that are not DLB role tokens: "
                         + ", ".join(safe(k) for k in unknown[:10])
                         + ". Keys must be role tokens (" + " ".join(KNOWN_ROLES)
                         + "); those entries are never checked.")

        entry = access.get(role)
        if entry is None or entry == "none" or entry == {}:
            done()
        if not isinstance(entry, dict):
            raise ParseError(f"the entry for {safe(role)} must be a map of "
                             f"{{mcp, tools, paths, connectors}}")
        bad = [k for k in entry if k not in ENTRY_KEYS]
        if bad:
            raise ParseError(f"unknown key {safe(bad[0])} in the entry for {safe(role)} "
                             f"(expected mcp, tools, paths, connectors)")
        lists = {k: as_list(entry.get(k), f"`{k}` for {safe(role)}") for k in ENTRY_KEYS}
    except ParseError as e:
        not_verified(f"could not parse `access:` in .claude/project.md ({e})", role)

    gaps = []

    # tools
    searched = os.environ.get("PATH", "")
    for t in lists["tools"]:
        if shutil.which(t):
            continue
        alt = None
        if "/" not in t:
            for d in SHIM_DIRS:
                cand = os.path.join(os.path.expanduser(d), t)
                if os.path.isfile(cand) and os.access(cand, os.X_OK):
                    alt = cand
                    break
        if alt:
            notes.append(f"Note: tool {safe(t)} found at {safe(alt, 160)} but not on this "
                         f"session's PATH ({safe(searched, 300)}). Call it by that path or add "
                         f"its directory to PATH.")
        else:
            gaps.append(f"tool {safe(t)} not found on PATH ({safe(searched, 300)}) or in "
                        + ", ".join(SHIM_DIRS))

    # paths: ~ then $VAR, relative to the project root (the dir holding .claude/project.md)
    for p in lists["paths"]:
        full = os.path.expandvars(os.path.expanduser(p))
        if not os.path.isabs(full):
            full = os.path.join(proj, full)
        if not os.path.exists(full):
            gaps.append(f"path {safe(p)} does not exist (resolved to {safe(full, 160)})")
        elif not os.access(full, os.R_OK):
            gaps.append(f"path {safe(p)} is not readable (resolved to {safe(full, 160)})")

    # mcp: configured keys only; names also listed under connectors are skipped
    skip = {c.lower() for c in lists["connectors"]}
    wanted = [s for s in lists["mcp"] if s.lower() not in skip]
    if wanted:
        names, problems = set(), []
        cfg, prob = load_json(os.path.join(home, ".claude.json"))
        if prob:
            problems.append(prob)
        if cfg:
            names |= server_keys(cfg.get("mcpServers"))
            projects = cfg.get("projects")
            if isinstance(projects, dict):
                mine = {os.path.realpath(x) for x in (start, proj)}
                for key, val in projects.items():
                    if isinstance(val, dict) and os.path.realpath(str(key)) in mine:
                        names |= server_keys(val.get("mcpServers"))
        for d in dict.fromkeys((proj, start)):
            local, prob = load_json(os.path.join(d, ".mcp.json"))
            if prob:
                problems.append(prob)
            if local:
                names |= server_keys(local.get("mcpServers"))
        missing = [s for s in wanted if s.lower() not in names]
        if missing:
            extra = f" ({'; '.join(problems)})" if problems else ""
            notes.append("Note: MCP server(s) " + ", ".join(safe(s) for s in missing)
                         + " not configured in ~/.claude.json (user scope or this project's "
                         "entry) or .mcp.json" + extra + ". If it is a claude.ai connector, list "
                         "it under `connectors:` instead; otherwise check it with `/mcp`.")

    if not gaps and not notes:
        return
    msg = [f"DLB access check for role {safe(role)} (from .claude/project.md `access:`):"]
    if gaps:
        msg.append("MISSING ACCESS:")
        msg += [f"  - {g}" for g in gaps]
    msg += notes
    if gaps:
        msg.append("Rule: if any access you need is missing, do not start that work and do NOT "
                   "ask another agent to do it for you. Call set_status(name, token, \"blocked\", "
                   "detail=\"missing access: <what>\"), tell the owner exactly what to add, and "
                   "tell pjm so it lands in the manifest's Access table.")
    emit("\n".join(msg))

try:
    main()
except SystemExit:
    raise
except BaseException as e:
    emit(f"DLB access check: access NOT verified: internal error ({type(e).__name__}: "
         f"{safe(e, 120)}). The hook failed open; check by hand or run /kickoff's access check.")
PY

rc=0
out=$(START="$START" python3 -c "$PYSRC" 2>/dev/null) || rc=$?

if [ "$rc" -eq 0 ]; then
  if [ -n "$out" ]; then printf '%s\n' "$out"; fi
else
  fallback "the checker exited with status $rc"
fi
exit 0
