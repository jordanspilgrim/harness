---
description: Stand up a right-sized agent fleet for execution — from a plan + handoff doc, or (with no args) bootstrap a minimal plan+handoff from a one-line goal. Reads the project descriptor, picks the roster profile, builds the manifest + task DAG, and launches one correctly-rooted session per role (desktop app or terminal).
argument-hint: "[plan-path] [handoff-doc-path]  (both optional — omit for minimal kickoff from a one-line goal)"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, TaskCreate, TaskUpdate
---

# /kickoff — descriptor-driven fleet setup from a plan + handoff

You are the **kickoff coordinator**. Set the harness up so a fleet of role threads can execute,
sized and shaped to THIS project. You do the setup one session can do, then **hand off one launch per
role** (prep + hand off — you do NOT drive the agents). The harness is project-agnostic:
**everything project-specific comes from `.claude/project.md`** (the descriptor; see
`~/.claude/agents/_templates/` or the harness `schema/project.md`).

**Two surfaces, one rule.** This runs in the desktop app and in a terminal. They differ in *how* a
thread gets its working directory, and that difference is the single highest-cost failure mode this
command has (see "Rooting" below). Everything else is identical.

**Inputs:** Plan `$1`, Handoff `$2` — **both optional**.
- **Both present & readable** → run the full **Procedure** below.
- **One or both missing/unreadable** → do NOT hard-stop. First offer the newest
  `.claude/plans/HANDOFF-*.md` (and its paired plan) if one plausibly fits. If none does — or the user
  wants to start fresh — run the **Minimal kickoff** path below to bootstrap a lightweight plan+handoff
  from a one-line goal, then continue into the Procedure with those as `$1`/`$2`. Either way, **never
  guess scope silently** — confirm the plan (given or drafted) with the user before creating anything.

## Minimal kickoff (no plan/handoff)

For a quick or small effort that doesn't have a written plan yet. The goal is to reach a *confirmed*
plan+handoff cheaply — not to skip planning. Keep this lane light: default to a `solo`/`small` roster.

1. **Get the goal.** If the user gave a one-line goal with the command, use it; else ask for one
   sentence: what should exist when this is done, and is it **this repo** or a **new project**? (A new
   project routes to `/harness-init` first — Procedure step 2.)
2. **Draft a thin plan + handoff (ideator-lite).** Write `.claude/plans/<slug>/plan.md` (goal, in-scope,
   out-of-scope, a concrete **acceptance/DoD** measured against the descriptor's `definition_of_done`,
   and 2-5 first tasks) and `.claude/plans/<slug>/HANDOFF.md` (proposed `roster_profile` — `solo` unless
   the goal clearly needs more — base ref, gates from the descriptor, and any owner decisions). Scope to
   what the goal states; don't invent adjacent work. Use `~/.claude/agents/_templates/` if present.
3. **Confirm before building.** Show the drafted plan + the proposed roster/gates and get an explicit
   OK (or edits). This replaces the given plan the full flow would have read — the confirmation gate is
   non-negotiable even in the minimal lane.
4. **Continue** into the Procedure from step 2, treating the drafted `plan.md`/`HANDOFF.md` as `$1`/`$2`.

If a descriptor doesn't exist yet, `/harness-init` (Procedure step 2) still runs first — minimal kickoff
drafts the *plan*, not the *descriptor*.

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
   - **Root** = descriptor `project_root`. If it is `none` or absent, resolve the repo's absolute
     path, confirm it with the user, and **write it into the descriptor before launching anything** —
     it is what the SessionStart assertion checks and what both contracts below are generated from.
     If it is set but disagrees with where this repo actually is, stop and reconcile with the user;
     do not silently prefer one.
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

7. **Hand off one launch per role**, in dependency order, using the surface's mechanism (see
   "Rooting" below — get this wrong and the whole fleet is wrong). Every launch, on either surface,
   MUST carry: the **root contract** (below); role identity + workspace; the model **and** effort
   tier from the README; the DLB register + supervised-monitor launch
   (`Monitor({command: "~/.claude/hooks/dlb-monitor-supervised.sh --name <name>", persistent: true})`,
   or note the auto-register hook does this if `.claude/.dlb-role` is set); which memory/topic files
   to load; the role's **first task** with inputs + handoff target + the **gate it must pass**
   (`check_cmd`/`test_cmd`/DoD from the descriptor); and a pointer to the manifest.

   - **Terminal** — emit one fenced, ready-to-paste block per role. Prefix each with the `cd` to its
     workspace and `export DLB_EXPECT_ROOT=<project_root>` so the SessionStart assertion has
     something to check. `/model` and `/effort` work here and belong in the block.
   - **Desktop app** — a session's working directory is fixed when the session is created and the
     agent cannot change it afterwards, so the **launcher** must set it. Spawning a session with a
     `cwd` does work: measured 2026-08-13, a session spawned with `cwd` under another repo rooted
     there, not in the parent. The widespread belief that desktop sessions are pinned to the parent
     repo and can only work cross-repo by absolute path is **false** — do not repeat it.

     Two details that change what you should emit:

     - **A spawned session lands in a fresh worktree of that repo** (`<repo>/.claude/worktrees/…`),
       not at the repo root. With `worktree_isolation: true` that is exactly right — each role gets
       its own tree for free. With `worktree_isolation: false` it is wrong: a project that wants one
       shared tree gets one worktree per role and the work fragments. For `false`, have the user open
       sessions at `<project_root>` directly (folder picker) rather than spawning them.
     - **`CLAUDE_PROJECT_DIR` is unset** in a spawned session, so anything reading it must fall back
       to `$PWD`. `dlb-autoregister.sh` does; don't write a launch block that depends on the variable.

     If you cannot set `cwd` for any reason, do NOT paste the block into a session rooted elsewhere.
     Tell the user to open a session at `<project_root>` and hand them the block for that session.

     `/model` and `/effort` are terminal dialogs and may not open here — state the tier in prose at
     the top of the block **and** tell the user to set it in the app's model selector, rather than
     assuming a slash command took.

8. **Surface owner-input items** as a short numbered list (batched — no interview modals).

## Rooting — the failure this command exists to prevent

A role thread rooted in the wrong repository is the most expensive failure this harness has produced,
and it is **silent by construction**. On 2026-08-12 eleven SAT threads ran for an hour rooted in
`baselineos-poc` instead of `sat-math-app`: each read the wrong `.claude/.dlb-role` (so
`dlb-autoregister` no-opped for all eleven), the wrong `CLAUDE.md`, and the wrong descriptor. A
misrouted thread is indistinguishable from an ordinary session, because the marker that would
identify it lives in the repo it failed to open. Nothing can notice from the inside. So the
expected root has to be carried in from outside — which is what the two contracts below do.

Two facts to state plainly rather than rediscover:

- **`EnterWorktree` cannot fix a wrong repo.** A sibling project is a separate repository, not a
  worktree of the one you are in, so it never appears in that repo's `git worktree list`. It is the
  right tool for a worktree of the *current* repo and useless for anything else.
- **Absolute paths are a contract, not a fix.** They work, and the misrouted SAT fleet shipped clean
  commits that way. But they hide the misrouting instead of correcting it, and they leak
  machine-specific paths into committed config (that fleet's `check_cmd` and `test_cmd` are still
  absolute today). Only use the cross-repo contract when rooting correctly is genuinely impossible,
  and say so out loud when you do.

**Root contract — put this at the top of every launch, both surfaces.** Generate it from the
descriptor's `project_root`; never hand-write it per fleet.

```
ROOT CONTRACT — before anything else.
This session must be rooted at: <project_root>
Your first action is `pwd`. If it prints anything else, STOP, tell the user both paths, and do not
start the task. Do not "work around it" with absolute paths — that is what hid a misrouted fleet for
an hour on 2026-08-12. EnterWorktree cannot fix it: <project_root> is a separate repository.
If `pwd` matches, ignore this block and use ordinary relative paths from here on.
```

**Cross-repo contract — only when the session genuinely cannot be rooted correctly**, and only with
the user's explicit agreement. Also generated from `project_root`:

```
CROSS-REPO CONTRACT — this session is rooted at <actual>; the project is at <project_root>.
1. Every path absolute, beginning <project_root>/ . Never relative, never ./, never cd.
2. Every git command is `git -C <project_root> ...` . Never a bare `git`.
3. Never `git add -A` or `git add .` — sibling threads share this tree. Stage your own files by path.
4. `index.lock` means another thread is mid-commit: wait a few seconds and retry.
5. Set DLB_ALLOW_ROOT_MISMATCH=1 so the SessionStart assertion stays quiet for this session only.
```

## Guardrails
- Prep only. Do NOT spawn agents, deploy, push, or take destructive/outward actions.
- **Every launch is rooted before it is briefed.** A thread that cannot be rooted at `project_root`
  does not get a task until the user has agreed to the cross-repo contract.
- **Never drop a project into the wrong repo** (step 2) — a new-stack project gets its own repo.
- Honor the descriptor: don't hardcode BaselineOS gates/roles/deploy — read them from `.claude/project.md`.
- If worktree_isolation, never mutate primary HEAD. Route mechanical/polling setup to Codex (README mechanical lane).
- If plan and handoff disagree on scope, surface it. Verify base ref, file existence, and roster with the user before creating anything.
