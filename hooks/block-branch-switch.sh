#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): enforces worktree isolation by
# blocking branch switches in the primary repo working tree.
#
# Why this exists
# ---------------
# This repo is opened in multiple Claude sessions concurrently against
# the same primary working tree. A `git checkout` from one session
# changes HEAD for all of them, silently corrupting in-flight work in
# the others.
#
# Documented incident: contracts-archive vs cris-stitching vs
# cris-nested vs feat/reskin overwrite loop on 2026-05-29 (4 hotfix
# overwrites in 9 hours). Root cause was branch state being mutated
# in the shared primary tree across concurrent sessions; the fix is
# structural — branch work happens in isolated worktrees under
# `.claude/worktrees/`, NOT in the primary.
#
# Behavior matrix
# ---------------
#                              primary worktree    secondary worktree
#   git checkout -- <file>     allowed             allowed
#   git checkout . / restore   allowed             allowed
#   git checkout <current>     allowed (no-op)     allowed (no-op)
#   git checkout <branch>      BLOCKED — no over-  blocked unless one-
#                              ride; use Enter-    shot marker allows
#                              Worktree instead
#   git checkout -b <new>      BLOCKED (same)      blocked unless marker
#   git checkout <sha>         BLOCKED (same)      blocked unless marker
#   git switch ...             BLOCKED (same)      blocked unless marker
#
# In secondary worktrees, the marker-based authorization
# (`.claude/.branch-switch-allow`, one-shot, consumed on use) still
# works — rebases legitimately need to detach HEAD and reattach the
# branch. The primary tree is hard-blocked with no override path.
#
# Scope
# -----
# This hook fires only on Claude tool calls (PreToolUse on Bash).
# Direct shell commands typed by a human in their terminal are not
# affected. The hook never blocks the user; it only blocks the agent.
#
# Authorization in secondary worktrees
# ------------------------------------
# When the user approves a switch in chat, the agent writes:
#     echo "<target-branch>" > .claude/.branch-switch-allow
# Or `*` to allow any single switch. The marker is consumed on use,
# so a stale approval can't grant silent future switches.

set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# ---------------------------------------------------------------------------
# Destructive working-tree commands: `git reset --hard` and `git clean -f*`.
#
# These DISCARD uncommitted work. In the PRIMARY tree that silently destroys
# other concurrent sessions' in-flight changes. Documented incident
# (2026-07-07): a background agent bare-`cd`'d into the primary tree and ran
# `git reset --hard`, discarding an uncommitted CLAUDE.md edit that was never
# recoverable (the reset also reverted a deleted lock file). checkout/switch
# were already hard-blocked here; reset --hard / clean were the remaining
# destructive gap. Hard-block them in the primary tree (no override); allow
# freely in secondary worktrees, where reset --hard is a normal rebase/build
# operation.
#
# Robustness (per code review):
#  - Quote-aware shlex tokenizer, so `--hard` inside a -m commit-message body
#    does not false-positive.
#  - Skips git GLOBAL options (`-C <path>`, `--git-dir[=]`, `--work-tree[=]`,
#    `-c k=v`, and other leading flags) when locating the subcommand, so
#    `git -C /primary reset --hard` is still detected.
#  - Resolves the command's EFFECTIVE target tree — a `-C`/`--work-tree`
#    target, else a preceding `cd <path>` in the same compound command, else
#    the CWD — and applies the primary-tree check against THAT tree. This
#    closes the `git -C /primary reset --hard` and `cd /primary && git reset
#    --hard` redirections that would otherwise slip a destructive op into the
#    primary tree from a secondary CWD.
#  - `git clean -n`/`--dry-run` is non-destructive even with -f, so it is not
#    flagged.
# The python emits two lines: "1"/"0" then the effective target dir (may be
# empty = use CWD). The checkout/switch block below resolves the same way
# (closed 2026-10-20 after `git -C <primary> checkout --detach` slipped through).
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  destructive_out=$(printf '%s' "$cmd" | python3 -c '
import sys, shlex

def tokenize(s):
    try:
        lex = shlex.shlex(s, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        raw = list(lex)
    except ValueError:
        return None
    out = []
    i = 0
    while i < len(raw):
        if raw[i] == "&" and i + 1 < len(raw) and raw[i+1] == "&":
            out.append("&&"); i += 2
        elif raw[i] == "|" and i + 1 < len(raw) and raw[i+1] == "|":
            out.append("||"); i += 2
        else:
            out.append(raw[i]); i += 1
    return out

tokens = tokenize(sys.stdin.read())
if tokens is None:
    print(0); sys.exit(0)

SEP = {";", "&&", "||", "&", "|"}
GLOBAL_VAL = {"-C", "--git-dir", "--work-tree", "-c", "--namespace",
              "--exec-path", "--super-prefix"}

last_cd = ""            # last `cd <path>` target seen before a git subcommand
at_subcmd_start = True
for i, tok in enumerate(tokens):
    if at_subcmd_start and tok == "cd":
        for t in tokens[i+1:]:
            if t in SEP:
                break
            if not t.startswith("-"):
                last_cd = t
                break
    if at_subcmd_start and tok == "git":
        seg = []
        for t in tokens[i+1:]:
            if t in SEP:
                break
            seg.append(t)
        # Walk past global options to the real subcommand; capture a target dir.
        target_dir = ""
        k = 0
        while k < len(seg):
            t = seg[k]
            if t in GLOBAL_VAL:
                if k + 1 < len(seg):
                    if t in ("-C", "--work-tree"):
                        target_dir = seg[k+1]
                    elif t == "--git-dir":
                        target_dir = seg[k+1]
                k += 2
                continue
            if t.startswith("--") and "=" in t:
                key, _, val = t.partition("=")
                if key in ("--work-tree", "--git-dir"):
                    target_dir = val
                k += 1
                continue
            if t.startswith("-"):
                k += 1
                continue
            break
        if k < len(seg):
            sub = seg[k]
            args = seg[k+1:]
            destructive = False
            if sub == "reset" and "--hard" in args:
                destructive = True
            elif sub == "clean":
                dry = ("--dry-run" in args) or any(
                    a.startswith("-") and not a.startswith("--") and "n" in a
                    for a in args)
                force = ("--force" in args) or any(
                    a.startswith("-") and not a.startswith("--") and "f" in a
                    for a in args)
                destructive = force and not dry
            if destructive:
                print(1)
                print(target_dir or last_cd or "")
                sys.exit(0)
    at_subcmd_start = tok in SEP
print(0)
' 2>/dev/null)
  is_destructive=$(printf '%s' "$destructive_out" | sed -n '1p')
  eff_dir=$(printf '%s' "$destructive_out" | sed -n '2p')
  if [ "$is_destructive" = "1" ]; then
    # Resolve which tree the command actually operates on.
    loc="."
    if [ -n "$eff_dir" ]; then
      case "$eff_dir" in
        */.git) eff_dir="${eff_dir%/.git}" ;;
        .git)   eff_dir="." ;;
      esac
      loc="$eff_dir"
    fi
    d_git_dir=$(git -C "$loc" rev-parse --absolute-git-dir 2>/dev/null || echo "")
    d_common_dir=$(git -C "$loc" rev-parse --git-common-dir 2>/dev/null || echo "")
    if [ -n "$d_common_dir" ]; then
      case "$d_common_dir" in
        /*) : ;;
        *)  d_common_dir=$(cd "$loc" 2>/dev/null && cd "$d_common_dir" 2>/dev/null && pwd || echo "$d_common_dir") ;;
      esac
    fi
    if [ -n "$d_git_dir" ] && [ "$d_git_dir" = "$d_common_dir" ]; then
      jq -nc --arg cmd "$cmd" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("Destructive git command (git reset --hard / git clean -f) is HARD-BLOCKED against the primary worktree by .claude/hooks/block-branch-switch.sh.\n\nThese discard uncommitted work. Multiple Claude sessions may hold in-flight changes in the primary tree; a reset --hard / clean here silently destroys them (documented 2026-07-07 incident: an unrecoverable discarded CLAUDE.md edit). This guard also covers -C / --git-dir / cd redirection into the primary tree.\n\nCommand attempted: " + $cmd + "\n\nThere is NO override in the primary tree. To discard or reset working state, do it inside an isolated worktree (EnterWorktree), never the primary tree. The user can run this command themselves in their own terminal.")
        }
      }'
      exit 0
    fi
    # Target is a secondary worktree (or not a repo) — reset --hard / clean are
    # normal there. Allow, and do not fall through to the checkout logic.
    exit 0
  fi
fi

# Detect whether any sub-command in $cmd is a `git checkout` or `git switch`
# invocation. The earlier implementation used a plain regex
# (`(^|[space;&|`(])git[space]+(checkout|switch)`), which false-positively
# matched the string "git checkout" appearing INSIDE a quoted argument —
# most painfully in `git commit -m "...git checkout..."` message bodies.
# That same string-match defeated the hook every time we tried to commit
# the hook itself with a behavior-matrix in the message.
#
# The fix tokenizes the command via python3's shlex (quote-aware) and
# walks the token stream, treating shell separators (`;` `&&` `||` `&` `|`)
# as sub-command boundaries. A "git checkout/switch" is real only when it
# starts a sub-command. If python3 is unavailable, fall back to the old
# regex — false-positives are annoying but safer than silently disabling
# the protection.
if command -v python3 >/dev/null 2>&1; then
  is_target_cmd=$(printf '%s' "$cmd" | python3 -c '
import sys, shlex

# Tokenize with punctuation_chars=True so shell separators (`;`, `&`, `|`,
# `<`, `>`) become standalone tokens even when written without surrounding
# whitespace (e.g. semicolon-attached suffix like `HEAD;git`). Without
# this, plain shlex.split groups the separator with its neighbor word
# (token becomes `HEAD;`) and we miss the sub-command boundary.
#
# Then collapse runs of `&&` / `||` (which split as `&`/`&` and `|`/`|`)
# back into a single separator token so the SEP membership check is uniform.
def tokenize(s):
    try:
        lex = shlex.shlex(s, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        raw = list(lex)
    except ValueError:
        return None
    out = []
    i = 0
    while i < len(raw):
        if raw[i] == "&" and i + 1 < len(raw) and raw[i+1] == "&":
            out.append("&&"); i += 2
        elif raw[i] == "|" and i + 1 < len(raw) and raw[i+1] == "|":
            out.append("||"); i += 2
        else:
            out.append(raw[i]); i += 1
    return out

data = sys.stdin.read()
tokens = tokenize(data)
if tokens is None:
    # shlex failed on an unbalanced quote — almost always an apostrophe inside a
    # heredoc body. Strip heredoc BODIES and retry so the quote-aware, position-
    # aware walk below can still run. This resolves the residual where a heredoc
    # that merely documents a git checkout got false-blocked (2026-07-22).
    # NOTE: this whole python -c block is single-quoted at the shell, so it must
    # contain NO apostrophes / single-quoted strings (that is the very bug being
    # fixed) — regex strings are double-quoted and quote chars come from chr().
    import re
    def strip_heredocs(s):
        q = "[" + chr(34) + chr(39) + "]?"   # optional quote char around the delimiter word
        start = re.compile("<<-?[ \\t]*" + q + "([A-Za-z_][A-Za-z0-9_]*)" + q)
        out = []; pos = 0
        while True:
            m = start.search(s, pos)
            if not m:
                out.append(s[pos:]); break
            nl = s.find("\n", m.end())
            if nl == -1:                       # no body on a following line
                out.append(s[pos:]); break
            close = re.compile("\\n[ \\t]*" + re.escape(m.group(1)) + "[ \\t]*(\\n|$)")
            cm = close.search(s, nl)
            if not cm:                         # unterminated — drop the rest
                out.append(s[pos:nl + 1]); break
            # keep the operator line (may hold a real command after `;`), drop the
            # body + the closing delimiter line, continue past it.
            out.append(s[pos:nl + 1]); pos = cm.end()
        return "".join(out)
    tokens = tokenize(strip_heredocs(data))
if tokens is None:
    # Still unparseable (malformed quoting OUTSIDE a heredoc — rare). Last-resort
    # command-boundary regex: block ONLY if a real git checkout|switch is present.
    import re
    print(1 if re.search(r"(^|[\s;&|`(])git\s+(checkout|switch)([\s]|$)", data) else 0)
    sys.exit(0)

SEP = {";", "&&", "||", "&", "|"}
GLOBAL_VAL = {"-C", "--git-dir", "--work-tree", "-c", "--namespace",
              "--exec-path", "--super-prefix"}
# Walk past git GLOBAL options (-C <dir>, --work-tree, -c k=v, ...) to the
# real subcommand, so `git -C /primary checkout X` is detected (2026-10-20 gap:
# only a bare `git checkout` was recognised). Emit: 1, the effective target dir
# (the -C/--work-tree/--git-dir value, else the last `cd` target, else empty =
# CWD), and the subcommand with its args.
last_cd = ""
at_subcmd_start = True
for i, tok in enumerate(tokens):
    if at_subcmd_start and tok == "cd":
        for t in tokens[i+1:]:
            if t in SEP:
                break
            if not t.startswith("-"):
                last_cd = t
                break
    if at_subcmd_start and tok == "git":
        seg = []
        for t in tokens[i+1:]:
            if t in SEP:
                break
            seg.append(t)
        target_dir = ""
        k = 0
        while k < len(seg):
            t = seg[k]
            if t in GLOBAL_VAL:
                if k + 1 < len(seg) and t in ("-C", "--work-tree", "--git-dir"):
                    target_dir = seg[k+1]
                k += 2
                continue
            if t.startswith("--") and "=" in t:
                key, _, val = t.partition("=")
                if key in ("--work-tree", "--git-dir"):
                    target_dir = val
                k += 1
                continue
            if t.startswith("-"):
                k += 1
                continue
            break
        # Exact subcommand match rejects checkout-index, switch-protocol, etc.
        if k < len(seg) and seg[k] in ("checkout", "switch"):
            print(1)
            print(target_dir or last_cd or "")
            print("git " + " ".join(seg[k:]))
            sys.exit(0)
    at_subcmd_start = tok in SEP
print(0)
' 2>/dev/null)
  co_out="$is_target_cmd"
  is_target_cmd=$(printf '%s\n' "$co_out" | sed -n '1p')
  co_dir=$(printf '%s\n' "$co_out" | sed -n '2p')
  co_part=$(printf '%s\n' "$co_out" | sed -n '3p')
  [ "$is_target_cmd" = "1" ] || exit 0
else
  # Fallback: legacy regex (matches the target-command substring anywhere,
  # including inside quoted strings). Triggers false-positives on commit
  # message bodies but does not let a real invocation slip past.
  if ! echo "$cmd" | grep -qE '(^|[[:space:];&|`(])git[[:space:]]+(checkout|switch)([[:space:]]|$)'; then
    exit 0
  fi
fi

# Isolate the `git checkout|switch ...` portion (stop at shell separators).
git_part="${co_part:-}"
[ -n "$git_part" ] || git_part=$(echo "$cmd" | grep -oE 'git[[:space:]]+(checkout|switch)([[:space:]][^;&|`)]*)?' | head -1)
# Resolve the tree the command acts on (-C / --work-tree / cd), not just the CWD.
loc="."
if [ -n "${co_dir:-}" ]; then
  case "$co_dir" in */.git) co_dir="${co_dir%/.git}" ;; .git) co_dir="." ;; esac
  loc="$co_dir"
fi

# Allow: file restore via `--` separator (e.g. `git checkout -- file.txt`).
if echo "$git_part" | grep -qE '[[:space:]]--([[:space:]]|$)'; then
  exit 0
fi

# Allow: working-tree restore via `git checkout .` or `git checkout ./path`.
if echo "$git_part" | grep -qE '[[:space:]]checkout[[:space:]]+\.($|[[:space:]/])'; then
  exit 0
fi

# Determine the likely target (last non-flag arg after checkout|switch).
target=$(echo "$git_part" | awk '{
  last=""
  for (i=3; i<=NF; i++) {
    if ($i !~ /^-/) last=$i
  }
  print last
}')

current_branch=$(git -C "$loc" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Allow: same-branch no-op (target matches current).
# (Not a no-op when it detaches or creates: --detach / -d, --orphan, -b/-B/-c/-C.)
if [ -n "$target" ] && [ "$target" = "$current_branch" ] \
   && ! echo "$git_part" | grep -qE '[[:space:]](--detach|-d|--orphan|-[bBcC])([[:space:]]|$)'; then
  exit 0
fi

# Determine whether we are in the PRIMARY worktree or a SECONDARY worktree.
#
# In the primary, `--git-dir` equals `--git-common-dir` (both point at the
# single `.git`). In a secondary, the git dir is
# `<primary>/.git/worktrees/<name>` while the common dir remains
# `<primary>/.git`. Resolve both to absolute paths because the primary
# returns a relative `.git` by default and equality comparisons need
# canonical forms.
git_dir=$(git -C "$loc" rev-parse --git-dir 2>/dev/null || echo "")
common_dir=$(git -C "$loc" rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$git_dir" ]; then
  git_dir=$(cd "$loc" 2>/dev/null && cd "$git_dir" 2>/dev/null && pwd || echo "$git_dir")
fi
if [ -n "$common_dir" ]; then
  common_dir=$(cd "$loc" 2>/dev/null && cd "$common_dir" 2>/dev/null && pwd || echo "$common_dir")
fi

is_primary="false"
if [ -n "$git_dir" ] && [ "$git_dir" = "$common_dir" ]; then
  is_primary="true"
fi

# Emit a JSON deny response and exit. PreToolUse hooks signal denial via the
# `hookSpecificOutput.permissionDecision` field; the exit code stays 0.
deny() {
  local reason="$1"
  jq -nc --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

if [ "$is_primary" = "true" ]; then
  # HARD BLOCK. No marker, no override. Branch work in the primary tree
  # is the documented root cause of the multi-session overwrite class
  # (see header comment). The only correct path is EnterWorktree.
  reason="Branch switching is HARD-BLOCKED in the primary worktree by .claude/hooks/block-branch-switch.sh.

Multiple Claude sessions may be reading from the primary tree. A surprise checkout here changes HEAD for all of them and corrupts in-flight work.

Command attempted: $cmd
Current branch:    ${current_branch:-(unknown)}
Target:            ${target:-(unparsed)}

There is NO MARKER OVERRIDE in the primary tree. Branch work must happen in an isolated worktree.

To proceed:
  - Create a new branch via the EnterWorktree tool:
        EnterWorktree({ name: \"<descriptive-name>\" })
        # creates .claude/worktrees/<name> on a new branch off origin/main

  - To work on an EXISTING branch (e.g. origin/feat/X):
        Bash: git worktree add .claude/worktrees/<name> origin/feat/X
        EnterWorktree({ path: \".claude/worktrees/<name>\" })

  - The user can switch branches manually in their own terminal — this hook only blocks Claude tool calls.

Why this restriction exists: the contracts-archive vs cris-stitching/cris-nested/feat-reskin overwrite loop on 2026-05-29 (4 hotfix overwrites in 9 hours) traced back to branch state being mutated in the shared primary tree across concurrent agent sessions. Worktree isolation makes that class of collision structurally impossible. See CLAUDE.md \"Branch isolation\" section."

  deny "$reason"
fi

# SECONDARY WORKTREE — keep the existing marker-based authorization so
# rebases (which detach HEAD and then reattach to the branch) keep working.
repo_root=$(git -C "$loc" rev-parse --show-toplevel 2>/dev/null || echo "")
marker="$repo_root/.claude/.branch-switch-allow"
if [ -n "$repo_root" ] && [ -f "$marker" ]; then
  # Match either a `*` wildcard line or an exact target line. Use FIXED-STRING
  # matching (grep -F), not a regex: the old regex `(\*|<target>)` became the
  # empty alternation `(\*|)` when target was empty (detached HEAD) and ugrep
  # errors on that, silently blocking. -F also avoids escaping the target.
  # Consume the marker on use so a stale approval cannot authorize future switches.
  if grep -qxF -- "*" "$marker" 2>/dev/null \
     || { [ -n "$target" ] && grep -qxF -- "$target" "$marker" 2>/dev/null; }; then
    rm -f "$marker"
    exit 0
  fi
fi

# Block (secondary worktree, no marker).
reason="Branch switching is blocked by .claude/hooks/block-branch-switch.sh.

You are in a secondary worktree at $repo_root, but no authorization marker is present.

Command attempted: $cmd
Current branch:    ${current_branch:-(unknown)}
Target branch:     ${target:-(unparsed)}

To proceed:
  - Ask the user explicitly for permission to switch branches.
  - If they approve, write the one-shot marker:
        echo \"$target\" > .claude/.branch-switch-allow
    then re-issue the checkout/switch command. The marker is consumed on use.
  - Or the user can: (a) run the command themselves, (b) temporarily disable the hook in .claude/settings.json."

deny "$reason"
