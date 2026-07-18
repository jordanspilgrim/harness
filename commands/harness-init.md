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

2. **Infer the stack**, then confirm with the user. Look for signals: `package.json` (Node/Next),
   `pyproject.toml`/`requirements.txt` (Python), `Cargo.toml` (Rust), `go.mod` (Go), a `run_demo.py`
   / `main.py` entrypoint, presence of a UI (`app/`, `src/components`, Tailwind) vs a plain
   library/CLI. Never guess silently — confirm stack, and derive sensible defaults for `check_cmd`
   and `test_cmd` from it (e.g. Python → `ruff check && mypy .` / `pytest`; Node → `npm run lint` or
   an `ai-check` script / the repo's test script).

3. **Gather the descriptor fields** (ask only what you can't infer; keep it to one batched round —
   no repeated modals): `name`, `stack`, `base_ref` (default `origin/main`), `worktree_isolation`
   (default `false` for a simple single-branch project, `true` for a multi-worktree fleet),
   `check_cmd`, `test_cmd` (or `none`), `definition_of_done` (the real "it works" check — e.g.
   `python run_demo.py` runs clean), `deploy_targets` (default `none`), `acceptance` (`web`/`cli`/
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

7. **Report** what was written and the one next step: run `/kickoff <plan> <handoff>` to stand up the
   fleet. Note that the global harness must be installed (`~/ClaudeCode/harness/install.sh`) for the
   roster/commands to resolve — check `~/.claude/commands/kickoff.md` exists; if not, tell the user
   to run the installer.

## Guardrails
- Per-project only. Do NOT copy the roster/commands/hooks into the repo — they resolve globally.
- Never clobber an existing `.claude/settings.json` / `.gitignore` — merge.
- Don't wire the branch-isolation hook unless `worktree_isolation: true` (a simple repo must keep
  normal branch switching).
- Confirm stack + gates with the user before writing — a wrong `check_cmd`/`test_cmd` misleads every role.
