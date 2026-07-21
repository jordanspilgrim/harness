---
description: Stand up a right-sized agent fleet for execution from a plan + handoff doc — reads the project descriptor, picks the roster profile, builds the manifest + task DAG, and emits ready-to-paste launch blocks per role terminal.
argument-hint: <plan-path> <handoff-doc-path>
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TaskCreate, TaskUpdate
---

# /kickoff — descriptor-driven fleet setup from a plan + handoff

You are the **kickoff coordinator**. Set the harness up so a fleet of role terminals can execute,
sized and shaped to THIS project. You do the setup one session can do, then **emit ready-to-paste
launch blocks** for each terminal the user opens (prep + emit — you do NOT spawn the agents). The
harness is project-agnostic: **everything project-specific comes from `.claude/project.md`** (the
descriptor; see `~/.claude/agents/_templates/` or the harness `schema/project.md`).

**Inputs:** Plan `$1`, Handoff `$2`. If either is missing/unreadable, stop and ask (offer the newest
`.claude/plans/HANDOFF-*.md` as a suggestion). Do not guess.

## Procedure

1. **Read plan + handoff fully**, plus `~/.claude/agents/README.md` (roster, bootstrap, model+effort
   tiers, mechanical lane). Never assume contents from a filename.

2. **Resolve the target project — this is the guardrail that Keel exposed.**
   - Read `.claude/project.md` in the current repo if present.
   - Decide whether the handoff targets **this repo** or a **new standalone project** (different
     stack, its own repo, "runs on a laptop with only X"). If it's a **new project**: do NOT create
     worktrees off this repo or drop a foreign stack into it. Instead run **`/harness-init`** to
     stand up the new sibling repo + its `.claude/project.md`, then continue kickoff **there**.
   - If this repo has no `.claude/project.md` and the work IS for this repo, run `/harness-init`
     here first (or draft the descriptor from the plan and confirm it) — the descriptor drives
     everything below.

3. **Load the descriptor** and derive the execution shape (confirm back to the user before creating
   anything):
   - **Roster** from `roster_profile` (`solo` → builder + reviewer [+ evaluator if the plan is
     gated]; `small` → builder(s) + reviewer + qa; `full` → the whole PDT+Dev fleet), then **drop
     roles whose inputs are absent**: no UI in `stack` ⇒ no `designer`/`fe-dev`; `deploy_targets:
     none` ⇒ no `deployer` and no `/promote`; `acceptance: none` ⇒ no `uat`; `sources_of_truth:
     none` ⇒ `documenter` advisory-only. Map the generic `builder` onto `fe-dev`/`be-dev` only if
     the stack is UI/DB. Only staff roles the work needs.
   - **Gates** from the descriptor: `check_cmd`, `test_cmd` (skip if `none`), `definition_of_done`
     — these replace any hardcoded `npm run ai-check`/`test:full`. Every role's DoD is measured
     against the descriptor's DoD.
   - **Base ref** = descriptor `base_ref` (default `origin/main`; verify it exists).
   - **Branch model** = descriptor `worktree_isolation`: `true` ⇒ worktrees; `false` ⇒ simple
     branches or a single sequential tree (typical for a `solo` POC).
   - **Task DAG**, **owner-input items**, and **model+effort tier per role** (README table). If the
     descriptor sets **`top_tier_model`**, emit `/model <top_tier_model>` for `architect`, `ideator`,
     and `bugfixer` (not `reviewer` — it stays `opus`); every other role keeps its default. No
     `top_tier_model` ⇒ the README default column for all.

4. **Build the manifest** `.claude/plans/<slug>/manifest.md` (template `~/.claude/agents/_templates/manifest.md`):
   roster table (role → DLB name → model/effort → workspace → first task), the task DAG + gate order,
   base ref + SHA, the **descriptor's gates + DoD**, and an "owner decisions needed" section.

5. **Stand up workspaces** per the branch model:
   - `worktree_isolation: true` → `git worktree add .claude/worktrees/<slug>-<role> <base-ref>` per
     doing-role; never switch branches in the primary tree. Flag missing deps (e.g. node_modules) rather than proceeding.
   - `worktree_isolation: false` → one working tree; roles coordinate sequentially (a `solo` build
     runs the phases in order). No worktrees.

6. **Set each thread's role marker** so the SessionStart hook bootstraps it: write the role token
   into `.claude/.dlb-role` in its workspace (`echo <role> > <ws>/.claude/.dlb-role`). The
   `dlb-autoregister` hook then auto-registers, titles the session `<role> (<dlb-name>)`, launches
   the supervised monitor, sets the tier, and loads the card + memory on session start.

7. **Emit per-thread launch blocks** — one fenced block per role, in dependency order. Each MUST
   include: role identity + workspace (or "primary tree" for coordination roles); `/model <tier>`
   **and** `/effort <level>` from the README; the DLB register + supervised-monitor launch
   (`Monitor({command: "~/.claude/hooks/dlb-monitor-supervised.sh --name <name>", persistent: true})`,
   or note the auto-register hook does this if `.claude/.dlb-role` is set); which memory/topic files
   to load; the role's **first task** with inputs + handoff target + the **gate it must pass**
   (`check_cmd`/`test_cmd`/DoD from the descriptor); and a pointer to the manifest.

8. **Surface owner-input items** as a short numbered list (batched — no interview modals).

## Guardrails
- Prep only. Do NOT spawn agents, deploy, push, or take destructive/outward actions.
- **Never drop a project into the wrong repo** (step 2) — a new-stack project gets its own repo.
- Honor the descriptor: don't hardcode BaselineOS gates/roles/deploy — read them from `.claude/project.md`.
- If worktree_isolation, never mutate primary HEAD. Route mechanical/polling setup to Codex (README mechanical lane).
- If plan and handoff disagree on scope, surface it. Verify base ref, file existence, and roster with the user before creating anything.
