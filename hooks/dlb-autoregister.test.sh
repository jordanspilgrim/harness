#!/usr/bin/env bash
# Regression test for dlb-autoregister.sh — the root assertion in particular.
# Run:  bash ~/.claude/hooks/dlb-autoregister.test.sh
#
# This hook is wired GLOBALLY (SessionStart, every project, 5s timeout) and ~/.claude/hooks
# symlinks into the harness working tree, so an edit here is live everywhere the instant it
# saves. Malformed JSON or a non-zero exit breaks session start in every repo at once. Every
# case below therefore asserts valid JSON and exit 0 in addition to the behaviour under test.
#
# The assertion is tested in BOTH directions on purpose. A check that fires on the misrouted
# case but ALSO fires on the correct one is worth nothing: always-red reads exactly like
# never-red. Each "fires" case below is paired with its benign neighbour.
set -uo pipefail
HOOK="${1:-$(cd "$(dirname "$0")" && pwd)/dlb-autoregister.sh}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

mkfixture() { # mkfixture <dirname> <project_root-value|-> [role]
  local d="$TMP/$1"; mkdir -p "$d/.claude"
  if [ "$2" != "-" ]; then
    printf '# desc\n\n```yaml\nname: %s\nstack: "x"\nproject_root: %s\n```\n' "$1" "$2" > "$d/.claude/project.md"
  else
    printf '# desc\n\n```yaml\nname: %s\nstack: "x"\n```\n' "$1" > "$d/.claude/project.md"
  fi
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$d/.claude/.dlb-role"
  printf '%s' "$d"
}

run() { # run <label> <NONE|substring|!substring> <env-assignments...> -- <projdir>
  local label="$1" expect="$2"; shift 2
  local env=(); while [ "$1" != "--" ]; do env+=("$1"); shift; done; shift
  local proj="$1" out rc
  # "${env[@]+...}" guards an empty array under set -u on bash 3.2 (macOS default).
  out=$(env -i PATH="$PATH" HOME="$HOME" CLAUDE_PROJECT_DIR="$proj" \
        ${env[@]+"${env[@]}"} bash "$HOOK" </dev/null 2>&1); rc=$?

  local why=""
  [ $rc -ne 0 ] && why="nonzero exit ($rc)"
  # Any output at all must be valid JSON — a broken hook breaks every session everywhere.
  if [ -z "$why" ] && [ -n "$out" ]; then
    printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || why="invalid JSON"
  fi
  if [ -z "$why" ]; then
    case "$expect" in
      NONE) [ -n "$out" ] && why="expected silence, got output" ;;
      # A leading ! asserts ABSENCE. Every "fires" case needs one of these on its benign
      # neighbour, otherwise a hook that fires unconditionally would pass the whole suite.
      !*)   printf '%s' "$out" | grep -q -- "${expect#!}" && why="should NOT contain '${expect#!}'" ;;
      *)    printf '%s' "$out" | grep -q -- "$expect" || why="missing '$expect'" ;;
    esac
  fi

  if [ -z "$why" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL  %-46s %s\n' "$label" "$why"
    [ -n "$out" ] && printf '      got: %.180s\n' "$(printf '%s' "$out" | tr '\n' ' ')"
  fi
}

RIGHT=$(mkfixture sat-math-app "$TMP/sat-math-app" pjm)     # correctly rooted, role set
WRONGD=$(mkfixture baselineos-poc "$TMP/baselineos-poc")    # a different repo, no role marker
NOROOT=$(mkfixture plain-repo - pjm)                        # descriptor without project_root
NOROOTNR=$(mkfixture quiet-repo -)                          # no project_root, no role
NODESC="$TMP/bare"; mkdir -p "$NODESC/.claude"; printf 'pjm\n' > "$NODESC/.claude/.dlb-role"
NONEVAL=$(mkfixture none-repo none pjm)                     # project_root: none
NOTHING="$TMP/nothing"; mkdir -p "$NOTHING"                 # no .claude at all

echo "— fires when the session is misrouted —"
# THE case this exists for: role marker lives in the repo you were meant to be in, so a
# misrouted session has NO role and looks ordinary. Must still fire.
run "misrouted, no role resolvable (the SAT case)" "WRONG WORKING DIRECTORY" \
    DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$WRONGD"
run "misrouted, role set via env"                  "WRONG WORKING DIRECTORY" \
    DLB_ROLE=pjm DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$WRONGD"
run "misrouted, names both repos"                  "sat-math-app" \
    DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$WRONGD"
run "misrouted, does NOT emit role bootstrap"      "WRONG WORKING DIRECTORY" \
    DLB_ROLE=pjm DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$WRONGD"
run "descriptor root moved to another repo"        "WRONG WORKING DIRECTORY" \
    DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$NOROOT"

echo "— stays silent when the session is correctly rooted (benign neighbours) —"
run "correct root + role  → bootstrap"             "AGENT ROLE BOOTSTRAP" -- "$RIGHT"
run "correct root + role  → NO wrong-repo banner"  '!WRONG WORKING DIRECTORY' -- "$RIGHT"
# Also assert the SOFT tier is absent. Without this, a hook whose outer compare is
# always-true still passes every negative above, because the basename tier quietly
# downgrades it to a note — caught by mutation-testing the outer compare.
run "correct root + role  → NO soft path note"     '!different path' -- "$RIGHT"
run "correct root + env agreeing → NO banner"      '!WRONG WORKING DIRECTORY' \
    DLB_EXPECT_ROOT="$TMP/sat-math-app" -- "$RIGHT"
run "correct root, no role → total silence"        "NONE" -- "$WRONGD"
run "descriptor without project_root → silence"    "NONE" -- "$NOROOTNR"
run "project_root: none treated as unset"          "AGENT ROLE BOOTSTRAP" -- "$NONEVAL"
run "project_root: none → NO banner"               '!WRONG WORKING DIRECTORY' -- "$NONEVAL"
run "override silences the check"                  '!WRONG WORKING DIRECTORY' \
    DLB_EXPECT_ROOT="$TMP/elsewhere-repo" DLB_ALLOW_ROOT_MISMATCH=1 -- "$RIGHT"

echo "— same repo name at a different path is NOT an error —"
SAMEBASE="$TMP/clone/sat-math-app"; mkdir -p "$SAMEBASE/.claude"
printf '# d\n\n```yaml\nname: sat-math-app\nproject_root: %s\n```\n' "$TMP/sat-math-app" > "$SAMEBASE/.claude/project.md"
printf 'pjm\n' > "$SAMEBASE/.claude/.dlb-role"
run "other clone → soft note, still bootstraps"    "AGENT ROLE BOOTSTRAP" -- "$SAMEBASE"
run "other clone → mentions the path mismatch"     "different path" -- "$SAMEBASE"
run "other clone → NOT the hard banner"            '!WRONG WORKING DIRECTORY' -- "$SAMEBASE"

echo "— a worktree of the expected repo is correctly rooted, not misrouted —"
# The fleet RUNS in worktrees, and the descriptor is committed, so every worktree carries
# a copy declaring the MAIN repo's path. Before the 2026-08-13 fix this halted every
# correctly-running worktree thread — an always-red gate, which is worth exactly as much
# as a never-red one. Both directions below.
WTIN="$TMP/sat-math-app/.claude/worktrees/sat-math-app-qa"; mkdir -p "$WTIN/.claude"
cp "$TMP/sat-math-app/.claude/project.md" "$WTIN/.claude/"; printf 'qa\n' > "$WTIN/.claude/.dlb-role"
run "worktree under the expected repo → OK"       "AGENT ROLE BOOTSTRAP" -- "$WTIN"
run "worktree under the expected repo → no halt"  '!WRONG WORKING DIRECTORY' -- "$WTIN"

if command -v git >/dev/null 2>&1; then
  GR="$TMP/realrepo"; mkdir -p "$GR/.claude"
  printf '# d\n\n```yaml\nname: realrepo\nproject_root: %s\n```\n' "$GR" > "$GR/.claude/project.md"
  printf 'qa\n' > "$GR/.claude/.dlb-role"
  ( cd "$GR" && git init -q . && git add -A && \
    git -c user.email=t@t -c user.name=t commit -qm init && \
    git worktree add -q "$TMP/outside-wt" -b wt ) >/dev/null 2>&1
  if [ -d "$TMP/outside-wt" ]; then
    run "linked worktree OUTSIDE the repo dir → OK"  "AGENT ROLE BOOTSTRAP" -- "$TMP/outside-wt"
    run "linked worktree OUTSIDE → no halt"          '!WRONG WORKING DIRECTORY' -- "$TMP/outside-wt"
  else
    echo "SKIP  linked-worktree cases (git worktree add failed)"
  fi
fi
# The benign neighbour must still halt: a directory that merely LOOKS worktree-shaped but
# belongs to a different repo is exactly the misrouting this gate exists for.
FAKEWT="$TMP/baselineos-poc/.claude/worktrees/sat-math-app-qa"; mkdir -p "$FAKEWT/.claude"
cp "$TMP/sat-math-app/.claude/project.md" "$FAKEWT/.claude/"; printf 'qa\n' > "$FAKEWT/.claude/.dlb-role"
run "worktree-shaped path in ANOTHER repo → halts" "WRONG WORKING DIRECTORY" -- "$FAKEWT"

echo "— role declared but nothing to resolve gates from —"
run "role set, repo has no descriptor"             "NO DESCRIPTOR" -- "$NODESC"
run "descriptor present → NO such warning"         '!NO DESCRIPTOR' -- "$RIGHT"

echo "— unchanged behaviour —"
run "unknown role token"                           "unknown role token" \
    DLB_ROLE=wizard -- "$RIGHT"
run "no role, no descriptor → silence"             "NONE" -- "$NOTHING"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
