# Agent Network — Product Development Lifecycle

The single source of truth for how the agent network operates — for **any** project. Every role
card in this directory is lean by design; the shared protocol lives **here** so it is
stated once (duplication across cards is drift). Read this file once when you adopt a
role, then follow your card.

Runtime model: **independent DLB threads**. Each role runs as its own Claude Code
session (a git worktree or terminal), loads its card, registers on DLB under its name,
and coordinates with peers via DLB messages. There is no single parent process — the
**Program Manager (`pjm`)** is the coordinator, not an orchestrator that spawns the others.

## Project descriptor — the harness is project-agnostic

The roster, commands, and hooks are shared across every project (installed globally from the
harness repo). **Everything project-specific comes from that repo's committed `.claude/project.md`**
(schema: `~/.claude/agents/_templates/` / the harness `schema/project.md`): the stack, the
`check_cmd`/`test_cmd` gates, the `definition_of_done`, `deploy_targets`, `acceptance` driver,
`product_context`, `sources_of_truth`, and the `roster_profile`. Roles and gates read those fields;
**where a field is absent or `none`, the role/step it drives does not apply** (no UI stack ⇒ no
`designer`/`fe-dev`; `deploy_targets: none` ⇒ no `deployer`/`/promote`; `acceptance: none` ⇒ no
`uat`). `/kickoff` reads the descriptor and stands up a right-sized fleet; `/harness-init` scaffolds
a descriptor into a new repo. Nothing below is BaselineOS-specific unless a descriptor makes it so.

## Two teams

- **PDT — Planning & Design Team:** `ideator` → `designer` → `architect`. Sets the stage.
  Deliverables are specs, not code. They must cross-validate feasibility before Dev starts.
- **Dev Team:** `pjm`, `builder` (→ `fe-dev`/`be-dev` on a UI/DB stack), `reviewer`, `qa`, `documenter`,
  `uat`, `deployer`, `bugfixer`. Turns approved specs into shipped, healthy production.

Which roles are actually staffed comes from the descriptor's `roster_profile` (**solo** = builder +
reviewer [+ evaluator]; **small** = builder(s) + reviewer + qa; **full** = the whole fleet) minus any
role whose descriptor inputs are absent. A one-person POC runs `solo`; the full PDT+Dev fleet is for
a large multi-surface product.

## Roster

| Role | Card | DLB name | Team | Owns (sole writer) |
|---|---|---|---|---|
| Ideator | `ideator.md` | `ideator` | PDT | `product-spec.md`, `uat-tests.md` |
| Designer | `designer.md` | `designer` | PDT | `design-spec.md`, `mockups/` |
| Architect | `architect.md` | `architect` | PDT | `eng-design.md`, `execution-plan.md` |
| Program Manager | `program-manager.md` | `pjm` | Dev | `delivery-plan.md`, `manifest.md` |
| Front-End Dev | `frontend-dev.md` | `fe-dev` | Dev | frontend code + `mockups/` sign-off notes |
| Back-End Dev | `backend-dev.md` | `be-dev` | Dev | backend code + migrations |
| Code Reviewer | `code-reviewer.md` | `reviewer` | Dev | `review-notes.md` |
| QA Tester | `qa-tester.md` | `qa` | Dev | `qa-report.md` |
| UAT Tester | `uat-tester.md` | `uat` | Dev | `uat-report.md` |
| Deployment Manager | `deployment-manager.md` | `deployer` | Dev | `changelog.md`, deploy records |
| Bug Fixer | `bug-fixer.md` | `bugfixer` | Dev | `incidents/` |
| Documenter | `documenter.md` | `documenter` | Dev | the project's `sources_of_truth` (or advisory-only if `none`) |

`fe-dev` and `be-dev` may be instantiated N times by `pjm` (e.g. `fe-dev-1`, `be-dev-2`);
each registers under its own suffixed DLB name and owns only the files in its assigned slice.

## Lifecycle & gates

```
PDT:   ideator ──▶ designer ──▶ architect ──▶ [PDT SIGN-OFF gate: all 3 + owner] ──▶ pjm
Dev:   pjm sizes+assigns ──▶ builder(s) ──▶ [GATE 1: code review]
       ──▶ [GATE 2: QA + Documenter — merge gate: check_cmd + test_cmd green] ──▶ merge to base_ref
       ──▶ [if deploy_targets: deployer deploys first env ──▶ GATE 3: UAT (per acceptance) ──▶ promote ladder]
       ──▶ [definition_of_done met] ──▶ bugfixer keeps it healthy (feeds bugs back)
```
The gates in brackets that reference `deploy_targets`/`acceptance` collapse to nothing when the
descriptor sets them to `none` — a `solo` POC's lifecycle is just: build ──▶ review ──▶ `definition_of_done`.

Every gate has a **pass route** (forward) and a **fail route** (back). A gate is never
skipped and never decided silently — see Priority & Scope rule in CLAUDE.md.

### Fail routes (mandatory)

| Gate fails | Default return | Escalate when |
|---|---|---|
| Code review | `fe-dev`/`be-dev` who wrote it, with `review-notes.md` | design/arch conflict → `pjm` routes to `architect` |
| QA | `fe-dev`/`be-dev` | spec ambiguity → `pjm` → `ideator` (change-control note) |
| UAT | `pjm` triages: impl→dev · design mismatch→`designer` · wrong criteria→`ideator` | — |
| Deploy (collision/migration) | `deployer` holds, notifies `pjm` + `architect` | schema/backfill risk → `architect` |
| Prod bug | `bugfixer` | systemic/design flaw → `architect`; scope call → `pjm` → the owner |
| Record (Documenter) | authoring doing-role, w/ uncited/contradictory claims by `path:line` | unanswerable scope/intent → `pjm` → the owner (quarantine item) |

## Artifact contract — single-writer rule

All feature artifacts live in `.claude/plans/<feature>/`. **Each file has exactly one
writer** (the owner in the roster). Everyone else reads. If you need a change to a file
you don't own, send a DLB message to its owner — never edit it yourself. This is the
core anti-collision, anti-drift mechanism.

```
.claude/plans/<feature>/
  manifest.md          ← pjm (index of truth: artifacts, gates, current owner, IDs)
  product-spec.md      ← ideator      uat-tests.md      ← ideator
  design-spec.md       ← designer     mockups/          ← designer
  eng-design.md        ← architect    execution-plan.md ← architect
  delivery-plan.md     ← pjm
  review-notes.md      ← reviewer     qa-report.md      ← qa
  uat-report.md        ← uat          changelog.md      ← deployer
  incidents/           ← bugfixer
```

## Traceability — stable IDs

`ideator` assigns `REQ-NN` (requirements) and `UAT-NN` (acceptance tests) in the spec.
**Every downstream artifact, task, PR, and test references these IDs — never restates
them in its own words.** A design element traces to a `REQ`; a dev task traces to a `REQ`;
a UAT run traces to a `UAT`. If a downstream role finds a gap, it cites the missing ID
back to `ideator` rather than inventing scope.

## The manifest — reorient here, always

`manifest.md` (written only by `pjm`) is how independent threads stay aligned.
On every wake, before acting, **read the manifest** to learn: current phase, which gates
have passed, who owns the ball, and the REQ/UAT index. If your understanding disagrees
with the manifest, the manifest wins — raise the discrepancy to `pjm` via DLB. Template
in `_templates/manifest.md`.

## Bootstrap — run this when you adopt a role

1. `register(name="<your dlb name>", working_on="<feature>")` on DLB → store `session_token`.
2. **Set your model AND effort tier** for this terminal (table below) — e.g. `/model claude-sonnet-5`
   then `/effort medium` for a coordination role. Don't leave a whole fleet on Opus/high by default;
   don't run a security review on `/effort medium` either. Both dials are per-role.
3. Launch the wake source (self-healing wrapper — respawns the monitor if it exits):
   `Monitor({command: "~/.claude/hooks/dlb-monitor-supervised.sh --name <your dlb name>", persistent: true})`.
4. **Load relevant memory.** Read `memory/MEMORY.md` and open every topic file whose Auto-Load trigger
   matches your task (subagents do NOT inherit the main session's auto-load discipline — this is why
   solved issues like `sales-exposed-visibility-model` kept getting re-litigated). When in doubt, read it.
5. Read `.claude/plans/<feature>/manifest.md`, then your card's **Inputs**.
6. Follow the DLB Inbox Protocol (in `~/.claude/CLAUDE.md`): reply-on-read to any task
   BEFORE starting work, `update_status` through `accepted → running → done`, report blockers.
7. Do your job per your card. Write ONLY the artifacts you own. Hand off per your card.

### Model + effort tiers (set `/model` and `/effort` on adopt)

Two dials. **Model** = capability/cost. **Effort** (`/effort low|medium|high|xhigh`) = how hard the model
reasons per turn. Tier BOTH by role — tier *down* on routing/verification turns to save tokens, tier *up*
on the judgment gates so review/security/architecture reason harder than the default (directly targets the
false-green / missed-bug failures from the 2026-07-17 review).

| Role | `/model` | `/effort` | Why |
|---|---|---|---|
| `architect` | opus → **`top_tier_model`** | **xhigh** | Design/feasibility gate. Lifts to the descriptor's `top_tier_model` (e.g. `claude-fable-5`) when set — long-horizon design is where Fable-tier earns its keep. |
| `ideator` | opus → **`top_tier_model`** | high | Foundational spec + acceptance authoring — the hardest specs benefit most from the top tier. |
| `bugfixer` | sonnet → **`top_tier_model`** | high | Root-cause reasoning under a live incident; long-horizon agentic strength suits it. |
| `reviewer` | opus | **xhigh** | The correctness/security/design gate. **Stays opus even when `top_tier_model` is set** — it owns the security pass and Fable-tier classifiers false-refuse on security-adjacent work. |
| `designer` | opus | high | Visual/UX judgment — not a coding/long-horizon task, so no Fable lift. |
| `fe-dev`, `be-dev` | sonnet | high | Real implementation + edge cases. |
| `deployer` | sonnet | high | Prod is high-stakes even when procedural — don't cut corners. |
| `pjm` | sonnet | **medium** | Coordination/routing, not deep reasoning — the biggest turn-volume role, so effort matters most here. |
| `qa`, `uat`, `documenter` | sonnet | **medium** | Structured verification / stewardship against a checklist. |
| watch / poll / scribe (ad-hoc) | haiku/Codex | low | Near-zero judgment — or move to Codex/script entirely (see "Mechanical lane"). |

> **`top_tier_model` (opt-in ceiling).** When the descriptor sets it (e.g. `claude-fable-5`), `/kickoff`
> emits `/model claude-fable-5` for `architect`/`ideator`/`bugfixer` instead of their default. It is **opt-in
> per project** because Fable-tier has real costs: always-on thinking → **minutes-long turns** (fine for deep
> design/root-cause, wasteful for mechanical roles — which is why only these three lift), it **requires ≥30-day
> data retention** (unavailable under ZDR), and over-prescriptive prompts *reduce* its quality (the lifted cards
> state goals, not step lists). `reviewer` never lifts (security-pass refusal risk). The **non-security
> adversarial-verify fan-out** in review workflows may run on `top_tier_model` at low effort — that's a
> workflow stage, not this standing card. No `top_tier_model` ⇒ every role uses the default column.

> **Terminal is the real lever** — the fleet runs as terminals, so `/model` + `/effort` on adopt is what
> actually bites. `model:`/`effort:` in a card's frontmatter apply when a role is *spawned as a subagent*
> (frontmatter `effort:` support is Claude-Code-version-dependent; the terminal `/effort` always works).
> Card frontmatter stays at the **default** tier (the safe floor); the `top_tier_model` lift is applied at the
> terminal by `/kickoff` reading the descriptor — so a subagent spawn in a project that hasn't opted in never
> silently lands on Fable. `CLAUDE_CODE_EFFORT_LEVEL` in the env enforces a floor across restarts if you want one.
> `pjm` (sonnet/medium) was the single largest token sink in the review; bump it up only if coordination slips.

### Engine parity — Codex equivalents (GPT-5.6 family)

If a role runs on **Codex** instead of Claude (e.g. onboarding users on a ChatGPT/Codex plan, or the
mechanical lane), use the equivalent tier below so capability stays consistent across engines. Codex is
**flat-rate**, so this is capability-matching, not cost-saving — but still tier by role: don't put the
frontier model on routing turns. Codex model order: `gpt-5.6-sol` (frontier agentic coder) ›
`gpt-5.6-terra` (balanced/everyday) › `gpt-5.6-luna` (fast/cheap). All support `low…xhigh` reasoning.
Invoke with `codex -m <model> -c model_reasoning_effort=<level>`.

| Role | Claude (model / effort) | Codex parity (model / reasoning) | Fit |
|---|---|---|---|
| `reviewer`, `architect` | opus / xhigh | **gpt-5.6-sol / xhigh** | Strong — frontier coder at top reasoning for the security/design gate. |
| `bugfixer` | sonnet / high | **gpt-5.6-sol / high** | Strong — Sol's long-horizon agentic strength suits root-cause work. |
| `fe-dev`, `be-dev`, `deployer` | sonnet / high | **gpt-5.6-terra / high** | Strong — balanced everyday coder; escalate to `sol` for hard tickets. |
| `qa`, `uat` | sonnet / medium | **gpt-5.6-terra / medium** | Good — checklist verification. |
| `pjm`, `documenter` | sonnet / medium | **gpt-5.6-luna / medium** | Good — coordination / stewardship, not deep coding. |
| `designer`, `ideator` | opus / high | **Claude-preferred** (fallback `gpt-5.6-sol / high`) | ⚠ Weaker — Codex is a *coding* agent; visual/UX + product ideation favor Claude. |
| mechanical lane / watchers | — | **gpt-5.6-luna / low** (or `gpt-5.4-mini`) | Sweeps, polling, boilerplate. |

> **Default Codex model = `gpt-5.6-terra`**, not `sol`. Reserve `sol` for the deep roles above (invoke
> explicitly with `-m gpt-5.6-sol`) — same reason you don't default every terminal to Opus. Pin the
> mechanical lane to `luna`.
>
> **No Codex equivalent for the `top_tier_model` lift.** `gpt-5.6-sol` is the Codex ceiling — a role that
> lifts to `claude-fable-5` on the Claude fleet maps to `sol / xhigh` on Codex (already the parity for
> `architect`/`bugfixer`). Don't try to over-map Fable onto a Codex model; Sol is as high as Codex goes.

## Mechanical lane — offload to Codex (flat-rate)

Codex CLI is installed and billed **flat-rate** (ChatGPT plan), so mechanical, high-volume, low-judgment
work should run on **Codex**, not on a premium Claude role burning metered tokens. Delegate via the
`codex` subagent (`subagent_type: "codex:codex-rescue"`) or the `/codex:rescue` skill; the diff comes back
into the normal review/QA gate.

- **Send to Codex:** em-dash / copy / label canonical sweeps; prettier & lint-fix sweeps; migration
  renumbering; deterministic seed-data authoring; date-bomb fixture fixes; mechanical CSS pins; and pure
  polling (test:full watch, CI/merge/deploy watch — often better as a plain script + `Monitor`). Run this
  lane on **`gpt-5.6-luna` at `low` reasoning** (fast/cheap; see the Codex-parity table) — not `sol`.
- **Keep on Claude:** anything needing judgment — spec/design authoring, review verdicts, the security
  pass, architecture, prod authorization, ambiguous or root-cause fixes.
- **Rule:** Codex output is a **draft, not a merge** — a Claude role still reviews every Codex diff through
  the normal `reviewer` → `qa` gate before it lands. Never let Codex self-merge.

## DLB message conventions

- Task assignment: `send(to, body, msg_type="task")`. Recipient replies immediately with
  ack + one-line plan + ETA, then `update_status(id,"accepted")`.
- Handoff: `send(to=<next role>, body="<feature> <ARTIFACT> ready for you @ <path> — REQ/UAT in scope: ...", msg_type="task")`.
- Gate result: sender reports pass/fail + the report path; on fail, include the fail-route target.
- Keep bodies short and cite paths + IDs, not restated content.
- **Liveness (DLB 0.5.0+):** call `set_status(name, session_token, status, detail)` as you work —
  `status ∈ {working, idle, blocked, done}`. Set `done` when you finish and `blocked` the moment you
  stall, so `pjm` reads real state from `list_threads` instead of guessing from `last_seen` (that proxy
  let dead threads sit undetected for hours in the 2026-07-17 review).
- **Lost your token to compaction? (DLB 0.4.0+)** call `recover_token(name)` — tokens are deterministic,
  so it returns your exact token; do NOT re-register (that trips the takeover gate). The
  `dlb-session-recover` SessionStart hook reminds you which names are registered on this machine.

### Coordination hygiene — keep relay turn-cost down

Every DLB message wakes the recipient for a full model turn against its cached context; in the
2026-07-17 review, relay/ack traffic was the single largest token line. Minimize it:

- **Don't send content-free acks as their own message.** "ack", "on it", "standing by", "registered
  and ready" each cost a full turn on both ends. Fold status into `set_status` + a `headline` on the
  next substantive message — `send(..., headline="ACK #742, ETA 20m")`. `headline` shows untruncated in
  `list_threads`/monitor previews, so the reader gets it **without opening the message or waking a turn**.
- **Batch owner decisions.** Collect decisions and present them as one numbered list (owner answers
  in a compressed batch). Do NOT open a per-agent interview modal for each question — the
  `block-interview-modal.sh` hook already blocks unsolicited modals; route questions through `pjm`/`decision-log`.
- **Report by exception.** Watchers/pollers should message only on the terminal event or a real blocker,
  not per poll. Prefer `headline` status updates over prose progress reports.
- **Read status before pinging.** Check `list_threads` (status + headline) before sending "any update?" —
  the answer is usually already there.

## Auto-registration & addressing

A thread declares its role once (per worktree), then registers itself automatically:

- Set the role by either `export DLB_ROLE=fe-dev` before launching, or write the token into
  `.claude/.dlb-role` in that worktree. `pjm` does this when it spins up a dev thread. The marker is
  gitignored (ephemeral per-worktree state).
- The `SessionStart` hook `~/.claude/hooks/dlb-autoregister.sh` (fires on startup **and resume/compact**)
  then injects a bootstrap directive telling the session its role + computed DLB name, and instructs it
  to `register` (with `force=true` to reclaim a stale name — 30-min takeover window), launch the
  **supervised monitor** (`~/.claude/hooks/dlb-monitor-supervised.sh`, self-heals if the monitor exits),
  set its model tier, and read its card + memory + the manifest. Because it re-fires on resume/compact,
  a thread whose monitor died in compaction self-heals without a human "restart your monitor" nudge.
  It also **titles the session** `<role> (<dlb-name>)` (collapsing to just the name for singletons, e.g.
  `pjm`; `fe-dev (fe-dev-2)` for scalable) via `hookSpecificOutput.sessionTitle`, so each thread's fleet
  identity is legible at a glance in the session list. (The statusline shows the same `·<name>` tag.)

**Naming rule:** singleton roles register under their canonical token (`ideator`, `designer`,
`architect`, `pjm`, `reviewer`, `qa`, `documenter`, `uat`, `deployer`, `bugfixer`) — only one is active at a
time. Scalable roles register unique: `fe-dev-<id>`, `be-dev-<id>`. Override with `DLB_NAME=…`
or force a suffix on any role with `DLB_INSTANCE=…`. (To make *every* thread uniquely suffixed,
remove the singleton case in the hook.)

**Addressing:** the DLB names in card handoff templates (`to="reviewer"`, `to="fe-dev"`, …) mean
"the current holder of that role, per the manifest roster." `pjm` records each thread's actual
registered name in `manifest.md`. To reach a scalable role, use its manifest name, or
`list_threads` and pick the active `fe-dev-*`. Singletons are reachable by their canonical token.
