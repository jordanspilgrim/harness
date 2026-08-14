---
description: Scaffold the harness into a new (or descriptor-less) project — writes .claude/project.md, the settings hook block, and .gitignore entries. The roster + commands resolve globally, so nothing heavy is copied.
argument-hint: "[project-name]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
---

# /harness-init — stand up the harness in a new project

Set up a fresh repo (or one missing a descriptor) to use the shared harness. The roster, `/kickoff`,
`/standup`, `/promote`, and the DLB/branch hooks are installed **globally** (see the harness repo's
`install.sh`) and merge into every project — so this command only writes the small **per-project**
pieces. Do NOT copy role cards or commands into the repo.

## Procedure

1. **Confirm the target repo.** Use the current working directory unless the user names another path.
   If it isn't a git repo yet, note that `git init` is needed (offer to run it). If a
   `.claude/project.md` already exists, show it and ask whether to edit rather than overwrite.

   **If the target is a NEW sibling repo** (a different stack, its own repository — the case
   `/kickoff` step 2 routes here), then this session is rooted in the *old* repo and will stay that
   way: a session's working directory is fixed when the session is created. Scaffolding the new repo
   from here is fine, since it is all file writes. **Continuing into `/kickoff` from here is not.**
   Create the directory and `git init` it, then request access to that path if the surface sandboxes
   directories (desktop: the directory-request tool; a terminal already has it), write the descriptor
   with `project_root` set to the new absolute path, and **stop**. The last thing you do is hand the
   user a correctly-rooted next step, not a task. See step 8.

2. **Infer the stack**, then confirm with the user. Look for signals: `package.json` (Node/Next),
   `pyproject.toml`/`requirements.txt` (Python), `Cargo.toml` (Rust), `go.mod` (Go), a `run_demo.py`
   / `main.py` entrypoint, presence of a UI (`app/`, `src/components`, Tailwind) vs a plain
   library/CLI. Never guess silently — confirm stack, and derive sensible defaults for `check_cmd`
   and `test_cmd` from it (e.g. Python → `ruff check && mypy .` / `pytest`; Node → `npm run lint` or
   an `ai-check` script / the repo's test script).

3. **Gather the descriptor fields** (ask only what you can't infer; keep it to one batched round —
   no repeated modals): `name`, `project_root` (the repo's absolute path — infer it, don't ask;
   this is what the SessionStart root assertion checks and what `/kickoff` generates launch
   contracts from, so set it on any repo that will ever host a fleet), `stack`, `base_ref`
   (default `origin/main`), `worktree_isolation`
   (default `false` for a simple single-branch project, `true` for a multi-worktree fleet),
   `check_cmd`, `test_cmd` (or `none`), `definition_of_done` (the real "it works" check — e.g.
   `pytest green + the CLI exits 0`; **never a billable or destructive command**, since every role
   runs it repeatedly and unattended), `deploy_targets` (default `none`), `acceptance` (`web`/`cli`/
   `none`), `product_context` (one line), `sources_of_truth` (default `none`), `roster_profile`
   (`solo`/`small`/`full` — default `solo` for a one-person POC).

4. **Write `.claude/project.md`** using the fenced-yaml format from the harness `schema/project.md`.
   Keep it tight; omit fields left at their defaults if that reads cleaner.

5. **Write `.claude/settings.json`** (merge if it exists — never clobber other keys) with the
   SessionStart hook so role threads auto-register/title:
   ```json
   { "hooks": { "SessionStart": [ { "matcher": "*", "hooks": [
     { "type": "command", "command": "bash ~/.claude/hooks/dlb-autoregister.sh SessionStart" } ] } ] } }
   ```
   **Only if `worktree_isolation: true`**, also add the PreToolUse/Bash branch-isolation hook:
   `{ "type": "command", "command": "bash ~/.claude/hooks/block-branch-switch.sh" }`.

6. **Add `.gitignore` entries** (create/append): `.claude/.dlb-role` and (if worktree_isolation)
   `.claude/worktrees/`.

7. **Write the bootstrap step** `scripts/harness-bootstrap.sh` (create the `scripts/` dir if needed,
   `chmod +x` it) so a fresh clone — a teammate or a new machine — installs the harness with one
   command instead of hand-wiring `~/.claude`. Write exactly this content:
   ```bash
   #!/usr/bin/env bash
   # Ensure the shared Claude Code agent harness is installed into ~/.claude.
   # Idempotent and safe to re-run. Requires read access to the harness repo.
   # Override the location/URL via env if your checkout lives elsewhere.
   set -euo pipefail
   HARNESS_DIR="${HARNESS_DIR:-$HOME/ClaudeCode/harness}"
   HARNESS_URL="${HARNESS_URL:-https://github.com/jordanspilgrim/harness.git}"
   if [ -d "$HARNESS_DIR/.git" ]; then
     echo "harness: refreshing $HARNESS_DIR"
     git -C "$HARNESS_DIR" pull --ff-only || true
   else
     echo "harness: cloning $HARNESS_URL -> $HARNESS_DIR"
     mkdir -p "$(dirname "$HARNESS_DIR")"
     git clone "$HARNESS_URL" "$HARNESS_DIR"
   fi
   "$HARNESS_DIR/install.sh"
   echo "harness: installed. Run /harness-init (if no .claude/project.md yet) then /kickoff."
   ```
   Then wire the project's task runner to it and add a one-line Setup note to the repo's README /
   CLAUDE.md, matching the stack — **do NOT use a package.json `postinstall`** (it runs in CI, which
   clones a private harness repo without creds and would fail every build):
   - Node: add `"bootstrap": "bash scripts/harness-bootstrap.sh"` to `package.json` scripts →
     `npm run bootstrap`.
   - Make-based: add a `bootstrap:` target → `make bootstrap`.
   - Otherwise: document `./scripts/harness-bootstrap.sh` directly.

8. **Report** what was written and the one next step: run `/kickoff <plan> <handoff>` to stand up the
   fleet. Note that the global harness must be installed (`~/ClaudeCode/harness/install.sh`, or the
   `scripts/harness-bootstrap.sh` you just wrote) for the roster/commands to resolve — check
   `~/.claude/commands/kickoff.md` exists; if not, tell the user to run the installer/bootstrap.

   **If you scaffolded a new sibling repo, the next step runs somewhere else, and saying so is the
   whole point of this step.** Do not run `/kickoff` from this session — it would stand the fleet up
   against the repo this session is rooted in, which is the misrouting `/kickoff`'s Rooting section
   exists to prevent. Instead tell the user, in one line each: the new repo's absolute path; that
   `/kickoff` must run in a session rooted *there*; and how to get one on their surface (desktop:
   open a session at that folder, or have the launcher spawn it with that `cwd`; terminal:
   `cd <path> && claude`). Verify the handoff is possible before promising it — if the new path is
   outside what this surface can open, say that plainly rather than leaving the user to discover it.

## Guardrails
- Per-project only. Do NOT copy the roster/commands/hooks into the repo — they resolve globally.
- Never clobber an existing `.claude/settings.json` / `.gitignore` — merge.
- Don't wire the branch-isolation hook unless `worktree_isolation: true` (a simple repo must keep
  normal branch switching).
- Confirm stack + gates with the user before writing — a wrong `check_cmd`/`test_cmd` misleads every role.
- **Never continue into `/kickoff` for a repo this session is not rooted in.** Scaffolding a sibling
  repo from here is fine; running its fleet from here is the misrouting failure. Hand off instead.
- Write `project_root` as an absolute path, and never write gates (`check_cmd`, `test_cmd`) as
  absolute paths to compensate for a badly-rooted session. Gates are relative to the repo; absolute
  gates are a symptom of misrouting and make the committed descriptor useless on any other machine.
