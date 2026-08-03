# `.claude/project.md` — the per-project descriptor

Every repo that uses the harness commits a `.claude/project.md`. It is the **only** thing that
differs between projects — the roster, commands, and hooks are shared (installed globally from this
harness repo). Roles and commands read these fields; where a field is absent or `none`, the step or
role it drives **does not apply**.

Format: a single fenced ```yaml block. Keep it short. Prose around it is for humans.

## Fields

| Field | Type | Default | Drives |
|---|---|---|---|
| `name` | string | dir name | labels, session titles |
| `stack` | string | (required) | architect/designer/fe-dev/be-dev Inputs; role selection (UI? DB?) |
| `base_ref` | string | `origin/main` | kickoff worktree/branch base |
| `worktree_isolation` | bool | `true` | whether the branch-isolation hook + worktrees apply |
| `check_cmd` | string | — | reviewer/qa/dev "lint+types+format" gate (e.g. `npm run ai-check`, `ruff check && mypy`) |
| `test_cmd` | string \| `none` | — | qa/dev test gate (e.g. `npm run test:full`, `pytest`) |
| `definition_of_done` | string | — | what "done" means, verified end-to-end (e.g. `pytest green + the CLI exits 0`). **Never name a billable or destructive command here** — every role runs this repeatedly |
| `deploy_targets` | list \| `none` | `none` | deployment-manager + `/promote`; `none` ⇒ both drop out |
| `acceptance` | `web` \| `cli` \| `none` + note | `none` | uat-tester driver (web+browser, run-CLI-assert-stdout, or skip) |
| `product_context` | string | — | ideator domain framing; reviewer threat lens |
| `sources_of_truth` | list + map \| `none` | `none` | documenter gate; `none` ⇒ documenter is advisory-only |
| `roster_profile` | `solo` \| `small` \| `full` | `small` | which roles kickoff stands up |
| `roles` | list | (from profile) | optional explicit override of the role set |
| `top_tier_model` | model id \| `none` | `none` | opt-in top tier for the high-judgment roles (`architect`, `ideator`, `bugfixer`) — see below |

### `top_tier_model` — opt-in ceiling for high-judgment roles

When set, `/kickoff` lifts `architect`, `ideator`, and `bugfixer` to that model instead of their
default tier (see the README model table). Leave `none` and every role uses its default. Two targets:

- **`claude-opus-5`** — the recommended top tier since Opus 5 shipped (2026-07-24): near-Fable
  capability at Opus pricing ($5/$25, half Fable), no data-retention requirement, normal turn lengths,
  standard prompting. Most valuable for `bugfixer` (default `sonnet`). No special guards.
- **`claude-fable-5`** — the absolute ceiling, only when a project genuinely needs it. Guards before
  opting in: it **requires ≥30-day data retention** and is unavailable under ZDR (the lifted roles
  error under ZDR — confirm plan/org retention first), and **over-prescriptive prompts** (`MUST`/
  `CRITICAL`, step-by-step scaffolding) *reduce* Fable-tier quality (the lifted cards state goals +
  constraints, not step lists). Its always-on thinking means minutes-long turns.

**`code-reviewer` is deliberately excluded** from the lift — it owns the security pass, and top-tier
safety classifiers can false-refuse on security-adjacent work (Trivy/SSRF/IDOR/tenancy), so the review
gate stays on its default (`opus`). Note that `opus` itself now resolves to Claude Opus 5, which also
carries elevated cyber safeguards — its card documents a `claude-opus-4-8` fallback for the rare
security-sub-pass refusal. Verify the chosen model is actually selectable on your plan (`/model`).

### `roster_profile` → default role set
- **solo** — `builder`, `reviewer` (+ `evaluator` if the plan is gated). Sequential; minimal DLB. One-person POC.
- **small** — `builder`(s), `reviewer`, `qa`. Light team.
- **full** — `ideator`, `designer`, `architect`, `pjm`, `fe-dev`, `be-dev`, `reviewer`, `qa`, `uat`, `deployer`, `bugfixer`, `documenter`. The BaselineOS fleet.

`builder` is the generic dev role. On a UI/DB stack it specializes into `fe-dev`/`be-dev`; on a
plain library/CLI it stays `builder`. Roles whose descriptor inputs are absent are dropped:
no UI stack ⇒ no `designer`/`fe-dev`; `deploy_targets: none` ⇒ no `deployer`/`/promote`;
`acceptance: none` ⇒ no `uat`; `sources_of_truth: none` ⇒ `documenter` advisory-only.

## Starter template (copy into `.claude/project.md`, fill in)

```yaml
name: my-project
stack: ""                      # e.g. "Python 3.11 + OpenAI SDK" or "Next.js 16 / React / Drizzle"
base_ref: origin/main
worktree_isolation: true       # false for a simple single-branch repo
check_cmd: ""                  # lint+format+types gate, e.g. "ruff check && mypy"
test_cmd: none                 # e.g. "pytest" — or none
definition_of_done: ""         # how done is verified end-to-end
deploy_targets: none           # or a list of envs
acceptance: none               # web | cli | none  (+ a short how-to note)
product_context: ""            # one line: what this is / who it's for
sources_of_truth: none         # or a doc set + which paths gate which doc
roster_profile: small          # solo | small | full
```

## Example — BaselineOS (reproduces today's behavior)

```yaml
name: baselineos
stack: "Next.js 16 App Router / React 19 / TypeScript / Tailwind v4 + shadcn / Plate.js; Drizzle ORM + better-sqlite3 (WAL); NextAuth v5 (JWT, multi-tenant via activeOrgId); AWS S3 + Secrets Manager; Anthropic/OpenAI/Gemini via src/lib/model-config.ts; Python doc-service"
base_ref: origin/main
worktree_isolation: true
check_cmd: npm run ai-check
test_cmd: npm run test:full
definition_of_done: "ai-check + test:full green → code review → QA → merge → UAT on testdot"
deploy_targets: [Test, Demo, App]   # test.baselineos.ai / demo.baselineos.ai / app.baselineos.ai — SSM + ECR ladder
acceptance: "web — QA-Clone browser on testdot (test.baselineos.ai); never demo/app"
product_context: "AI legal-workflow SaaS for attorneys; multi-tenant (Organization→Team→User)"
sources_of_truth: "ARCHITECTURE.md (infra/db/auth/model-config), DESIGN.md (tokens/globals.css), FEATURES.md (routes/flags/skills)"
roster_profile: full
top_tier_model: claude-opus-5    # lifts architect/ideator/bugfixer (near-Fable at half cost); reviewer stays opus (security pass)
```

## Example — standalone single-person POC

```yaml
name: my-poc
stack: "Python 3.11 + OpenAI SDK (+ scikit-learn)"
base_ref: origin/main
worktree_isolation: false
check_cmd: "ruff check && mypy ."   # ONLY if both are actually installed — verify, don't assume
test_cmd: pytest
definition_of_done: "pytest green + <a cheap, repeatable end-to-end check>"
deploy_targets: none
acceptance: "cli — assert expected stdout / artifacts from a NON-billable entrypoint"
product_context: "<one-line POC problem statement from the plan>"
sources_of_truth: none          # README.md only; documenter advisory
roster_profile: solo
```

> **Never put a billable or destructive command in `definition_of_done` or `acceptance`.** These
> two fields are read by every role as "the thing to run to prove you are finished", so a demo
> entrypoint that calls a paid API, overwrites committed artifacts, or mutates a shared database
> will be run repeatedly, by several threads, unattended. If the only true end-to-end check is
> expensive, say so in the field text and name the cheap proxy the fleet should actually run.
>
> Real example: an earlier version of this template used a POC's `run_demo.py` for both fields.
> That script spends real money per run and overwrites the committed artifacts backing a
> pre-registered published metric. The project's own `.claude/project.md` now overrides it with
> `NEVER run run_demo.py`.
