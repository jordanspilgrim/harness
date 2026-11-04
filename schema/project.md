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
| `project_root` | abs path \| `none` | `none` | **root assertion** — the hook halts a session rooted in the wrong repo; `/kickoff` builds the cross-repo preamble from it |
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
| `access` | map role token to {`mcp`, `connectors`, `tools`, `paths`} \| `none` | `none` | **access check**: `/kickoff` verifies each role's access before launching it, and a role with a gap is not launched. See below |

### `project_root` — the absolute path this repo lives at

Set this on the machine that runs the fleet. `dlb-autoregister.sh` compares it against the session's
actual working directory on every SessionStart, and `/kickoff` uses it to build launch prompts.

**Why it exists.** A session rooted in the wrong repo is the most expensive failure this harness has
produced. On 2026-08-12 eleven SAT threads ran for an hour rooted in `baselineos-poc` instead of
`sat-math-app`. Every one read the wrong `.claude/.dlb-role` (so the autoregister hook silently
no-opped for all eleven), the wrong `CLAUDE.md`, and the wrong descriptor. Nothing reported anything,
because the misrouted case is exactly the case where the role never resolves — a thread that should
be a fleet member is indistinguishable from an ordinary session. The workaround (absolute paths
everywhere) then leaked into that project's committed `check_cmd`/`test_cmd`, making the descriptor
non-portable. This field is what makes that state detectable in the first ten seconds instead of the
sixtieth minute.

**Two tiers, so a second clone is not an error.** A different *basename* means a different repo, which
halts the thread. A matching basename at a different path just means another clone or machine, which
is a one-line note. That keeps the committed descriptor usable by a teammate whose checkout lives
elsewhere: they get the note, not the banner.

Leave it `none` on a repo that is only ever opened directly and never hosts a fleet. Set
`DLB_ALLOW_ROOT_MISMATCH=1` for a session that is deliberately cross-repo, or `DLB_EXPECT_ROOT=<path>`
to assert a root from a launcher without a descriptor. Regression test:
`bash ~/.claude/hooks/dlb-autoregister.test.sh` (21 cases, each "fires" case paired with the benign
neighbour it must stay silent on).

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

### `access`: what each role needs to reach

A map from DLB role token to the MCP servers, claude.ai connectors, CLI tools, and filesystem paths
that role must be able to use. `/kickoff` checks every entry before it launches the role (see its
access-check step) and records the result in the manifest's Access table.

Keys are DLB role tokens, the same tokens `.claude/.dlb-role` and `DLB_ROLE` take: `ideator`,
`designer`, `architect`, `pjm`, `fe-dev`, `be-dev`, `reviewer`, `qa`, `uat`, `deployer`,
`bugfixer`, `documenter`. `/kickoff` rejects any other key, and the hook warns about one. A builder
is keyed as `fe-dev` or `be-dev`.

```yaml
access:
  ideator:
    mcp: [slack]                   # keys under mcpServers in ~/.claude.json or .mcp.json
    connectors: [notion]           # claude.ai connectors; verified by /kickoff, not checkable offline
    tools: [gh]                    # executables that must resolve on PATH
    paths: [~/Documents/specs]     # must exist and be readable
  be-dev:
    tools: [uv, docker]
    paths: [specs, "$DATA_DIR/fixtures"]
```

Entry keys:

- `mcp`: MCP servers configured in Claude Code itself. The name is the key under `mcpServers` in
  `~/.claude.json` (user scope, or the `projects` entry for this repo) or in `.mcp.json`.
- `connectors`: claude.ai connectors (Notion, Gmail, Drive and the like). No local file records
  them, so only `/kickoff`, which can see the session's tool list, verifies them.
- `tools`: executables that must resolve on the session's PATH.
- `paths`: files or directories that must exist and be readable. `~` and `$VAR` expand. A
  relative path resolves against the project root, the directory that holds `.claude/project.md`,
  wherever the session itself is rooted.

**Why it exists.** Agents route around missing access instead of reporting it. In one fleet the
product thread had no Notion connector, so it quietly asked another agent to read and write Notion
on its behalf. The work got done, but through a relay nobody approved: the second agent acted
outside its lane, its own task stalled, and the real gap (a connector the owner had to add) stayed
invisible until someone read both transcripts. A declared access list turns that into a check that
fails at launch, and the bootstrap rule (README, "Missing access") turns a mid-task discovery into a
`set_status(blocked)` the owner can see.

Rules:

- A role with a failed check is **not launched**. The gap goes to the owner as an input item, the
  same as a missing credential.
- A role absent from the map is assumed to need nothing beyond the repo. `access: none` disables the
  check entirely.
- List only what the role cannot do its job without. Optional conveniences do not belong here.
- Never satisfy one role's gap by routing its work through another role. Fix the access, or change
  the plan with the owner.

**Optional: re-check at every session start.** `/kickoff` checks once, at launch. To catch a gap
that appears later (a tool uninstalled, a path unmounted, an MCP server removed from config), wire
`bash ~/.claude/hooks/dlb-access-check.sh SessionStart` as a SessionStart hook with a 5s timeout. It
resolves the role the same way `dlb-autoregister.sh` does and checks that role's entry locally:

- tools on PATH. A tool found only in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, or
  `~/.cargo/bin` is reported as "not on this session's PATH". A tool found nowhere is a gap, and the
  report names the PATH searched.
- paths exist and are readable.
- each `mcp` name is a configured key in `~/.claude.json` (user scope or this project's entry) or
  `.mcp.json`. It checks config keys, not connection state. A name that is not configured is a
  one-line note, not a gap. `connectors` are skipped.

It stays silent when there is nothing to report. A hard gap (a missing tool or path) injects the
blocked rule. Notes alone (an unconfigured MCP name, a tool off PATH, a key that is not a role
token, a second yaml fence) inject one line each without the rule. A descriptor it cannot parse,
or any internal error, produces "access NOT verified: <reason>" rather than silence. Regression
test: `bash ~/.claude/hooks/dlb-access-check.test.sh` (75 cases, each "fires" case paired with the
benign neighbour it must stay silent on).

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
project_root: none             # abs path this repo lives at — set it if a fleet ever runs here
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
access: none                   # or role token: {mcp, connectors, tools, paths}; kickoff blocks a role with a gap
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
