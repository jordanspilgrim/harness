#!/usr/bin/env bash
# Regression test for block-branch-switch.sh.
# Run from inside the repo:  bash .claude/hooks/block-branch-switch.test.sh
# Feeds crafted {"tool_input":{"command":...}} JSON into the hook and asserts
# its allow/deny decisions. Works from either the primary or a secondary
# worktree (destructive-command expectations flip between the two).
#
# Covers the two false-block classes fixed 2026-07-22:
#   - shlex parse-failure on an apostrophe / quote-imbalance (heredoc body) that
#     used to hard-block ANY such command; and
#   - a heredoc that merely *documents* a branch switch (the residual), now
#     handled by stripping heredoc bodies and retrying the quote-aware walk.
# Plus the destructive-command guard (reset --hard / clean -f) and the real
# branch switches that must always block.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/block-branch-switch.sh"
CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
# Are we in the primary worktree? (git-dir == common-dir). Destructive commands
# hard-block in the primary tree and are allowed in secondary worktrees.
gd=$(git rev-parse --git-dir 2>/dev/null); cd_=$(git rev-parse --git-common-dir 2>/dev/null)
gd=$(cd "$gd" 2>/dev/null && pwd || echo x); cd_=$(cd "$cd_" 2>/dev/null && pwd || echo y)
[ "$gd" = "$cd_" ] && DESTRUCTIVE=deny || DESTRUCTIVE=allow
# Split trigger words so running THIS test never itself trips a live hook.
GC="git che""ckout"; GS="git swi""tch"; RS="git re""set"; CN="git cl""ean"
pass=0; fail=0
run() { local expect="$1" cmd="$2" out got=allow
  out=$(printf '%s' "$cmd" | jq -Rs '{tool_input:{command:.}}' | bash "$HOOK" 2>/dev/null)
  printf '%s' "$out" | grep -q '"permissionDecision": *"deny"' && got=deny
  if [ "$got" = "$expect" ]; then pass=$((pass+1));
  else fail=$((fail+1)); printf 'FAIL want=%s got=%s :: %s\n' "$expect" "$got" "${cmd%%$'\n'*}"; fi
}

# Real branch switches — always block (primary hard-block; secondary needs a marker).
run deny "$GC feature-x"
run deny "$GC -b feat/x"
run deny "$GS feature-y"
run deny "$GC 1a2b3c4d"
run deny "foo && $GS bar"
run deny "$GC feat/x; npm test"

# 2026-10-20 gap: git GLOBAL options before the subcommand, and a target tree
# other than the CWD. PRIMARY must be the primary worktree path.
PRIMARY="${PRIMARY:-$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')}"
run deny "git -C $PRIMARY che""ckout --detach 1a2b3c4d"
run deny "git -C $PRIMARY swi""tch --detach main"
run deny "git -c core.x=y -C $PRIMARY che""ckout feature-x"
run deny "git --work-tree=$PRIMARY che""ckout feature-x"
run deny "cd $PRIMARY && $GC feature-x"
run allow "git -C $PRIMARY che""ckout -- README.md"
run allow "git -C $PRIMARY che""ckout-index -a"
run allow "git -C $PRIMARY status"

# Benign commands that merely contain the words / an apostrophe — must allow.
run allow "cat >> ledger.md <<'EOF'
don't trust it — apostrophes must not block
EOF"
run allow "cat > doc.md <<'EOF'
To switch branches:
$GC <branch>
EOF"
run allow "git commit -m \"how to $GC a branch (in the message)\""
run allow "grep -qE 'git (checkout|switch)' file.md"
run allow "sed -i \"s/x/don't/\" file"
run allow "$GC -- file.txt"        # file restore
run allow "$GC ."                  # working-tree restore
run allow "$GC $CUR"               # no-op to current branch

# Destructive working-tree commands — deny in primary, allow in secondary.
run "$DESTRUCTIVE" "$RS --hard"
run "$DESTRUCTIVE" "$RS --hard HEAD~1"
run "$DESTRUCTIVE" "$CN -fd"
# Non-destructive variants — always allow.
run allow "$RS --soft HEAD~1"
run allow "$CN -n"
run allow "git commit -m \"note: reset --hard is dangerous\""

echo "block-branch-switch regression (${DESTRUCTIVE}-in-this-tree): pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
