#!/usr/bin/env bash
# Project post-checkout hook: restore the primary branch after Claude checkouts.
# No force/reset/clean: Git must be able to carry every working-tree change.
set -uo pipefail
[ "${HARNESS_POSTCHECKOUT_RECOVERING:-}" = 1 ] && exit 0
[ "${CLAUDECODE:-}" = 1 ] || exit 0
[ "${3:-}" = 1 ] || exit 0

git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
git_dir=$(cd "$git_dir" && pwd -P) || exit 0
common_dir=$(cd "$common_dir" && pwd -P) || exit 0
[ "$git_dir" = "$common_dir" ] || exit 0

found_ref=$(git symbolic-ref --quiet HEAD 2>/dev/null) || found_ref=''
found=${found_ref#refs/heads/}
[ -n "$found" ] || found="DETACHED@$(git rev-parse HEAD 2>/dev/null)"
alert() {
  local line
  printf -v line 'HARNESS ALERT %s cwd=%q HEAD=%q: %s' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$PWD" "$found" "$1"
  printf '%s\n' "$line" >&2
  if ! { mkdir -p "$HOME/.claude" && printf '%s\n' "$line" >> "$HOME/.claude/harness-alerts.log"; }; then
    printf 'HARNESS ALERT: could not write ~/.claude/harness-alerts.log\n' >&2
  fi
}

# The primary Git directory alone does not identify the working tree: callers
# can independently supply --work-tree or GIT_WORK_TREE. Compare physical paths.
actual_tree=$(git rev-parse --show-toplevel 2>/dev/null) || actual_tree=''
primary_tree=''
IFS= read -r -d '' primary_tree < <(git worktree list --porcelain -z 2>/dev/null) || primary_tree=''
primary_tree=${primary_tree#worktree }
actual_tree=$(cd "$actual_tree" 2>/dev/null && pwd -P) || actual_tree=''
primary_tree=$(cd "$primary_tree" 2>/dev/null && pwd -P) || primary_tree=''
if [ -z "$actual_tree" ] || [ -z "$primary_tree" ] || [ "$actual_tree" != "$primary_tree" ]; then
  alert "RECOVERY REFUSED: actual working tree is not the primary worktree; no recovery attempted."
  exit 1
fi

primary=$(git config --get harness.primaryBranch 2>/dev/null) || primary=''
if [ -z "$primary" ]; then
  default_ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || default_ref=''
  primary=${default_ref#refs/remotes/origin/}
  if [ -z "$primary" ]; then
    primary=$(git config --get init.defaultBranch 2>/dev/null) || primary=''
    if [ -z "$primary" ]; then
      for candidate in main master; do
        if git show-ref --verify --quiet "refs/heads/$candidate"; then
          primary=$candidate
          break
        fi
      done
    fi
  fi
fi
if [ -z "$primary" ] || ! git show-ref --verify --quiet "refs/heads/$primary"; then
  alert "Cannot resolve primary branch; set git config harness.primaryBranch <branch>. No recovery attempted."
  exit 1
fi
[ "$found_ref" = "refs/heads/$primary" ] && exit 0

# Resolve the branch once. Branch-dependent config may change during recovery;
# the inherited sentinel stops the nested hook before it resolves another target.
# Git must also refuse ignored-file collisions, just like tracked/untracked ones.
if (unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    HARNESS_POSTCHECKOUT_RECOVERING=1 git -C "$primary_tree" --work-tree="$primary_tree" switch --no-overwrite-ignore -- "$primary"); then
  alert "Unexpected Claude checkout in primary worktree; restored $primary."
else
  alert "RECOVERY FAILED: could not restore $primary safely; HEAD left as found. Inspect working-tree changes; no force used."
  exit 1
fi
