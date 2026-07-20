# harness — a project-agnostic Claude Code agent fleet

A reusable multi-agent development harness: a role roster, coordination commands, and DLB/branch
hooks that work for **any** project. Installed once into `~/.claude`, it merges into every repo;
what differs per project lives in that repo's committed **`.claude/project.md`** descriptor.

Born from BaselineOS (a Next.js legal-workflow SaaS), then generalized when a standalone Python POC
("Keel") needed the same fleet without the BaselineOS stack, pipeline, or history.

## What's here

```
agents/     role cards (ideator, architect, designer, program-manager, frontend-dev, backend-dev,
            code-reviewer, qa-tester, uat-tester, deployment-manager, bug-fixer, documenter) +
            README.md (the shared protocol: teams, lifecycle, single-writer artifact contract,
            traceability, bootstrap, model+effort tiers, Codex engine-parity, DLB conventions) +
            _templates/ (manifest + artifact skeletons)
commands/   kickoff.md (descriptor-driven fleet setup) · standup.md (DLB liveness) ·
            promote.md (deploy-gated) · harness-init.md (scaffold a new project's descriptor)
hooks/      dlb-autoregister.sh (SessionStart role→DLB bootstrap + session titling) ·
            dlb-monitor-supervised.sh (self-healing wake source) · block-branch-switch.sh
            (worktree isolation — wired per-project only when worktree_isolation: true)
schema/     project.md — the descriptor spec + starter template + worked examples
install.sh  symlink agents/ commands/ hooks/ into ~/.claude (idempotent)
bootstrap.sh            refresh this checkout (git pull --ff-only) then re-run install.sh
templates/project-bootstrap.sh   self-contained clone-or-pull + install; /harness-init drops a
            copy of this into each project as scripts/harness-bootstrap.sh
```

## Install

```bash
git clone <this-repo> ~/ClaudeCode/harness   # or wherever
~/ClaudeCode/harness/install.sh              # symlinks into ~/.claude/{agents,commands,hooks}
```
Then add the `dlb-autoregister` SessionStart hook to `~/.claude/settings.json` (the installer prints
the exact block). DLB itself: `uv tool install dlb-mcp` and configure the `dlb` MCP server.

To refresh an existing checkout to latest and reinstall in one step: `~/ClaudeCode/harness/bootstrap.sh`.

### Per-project bootstrap (teammates / fresh clones)

`/harness-init` drops `scripts/harness-bootstrap.sh` into each project (a copy of
[`templates/project-bootstrap.sh`](templates/project-bootstrap.sh)). It's self-contained: it clones
or fast-forwards the harness into `~/ClaudeCode/harness`, then runs `install.sh`. So anyone who clones
a harness-using repo gets the fleet with one command — `npm run bootstrap` (Node), `make bootstrap`,
or `./scripts/harness-bootstrap.sh` — with no manual `~/.claude` wiring. It's **not** a package.json
`postinstall`: that runs in CI, which clones the private harness repo without credentials and would
fail every build. Override the harness location/URL with `HARNESS_DIR` / `HARNESS_URL`.

## Use it in a project

```bash
cd ~/ClaudeCode/my-new-project
# in a Claude Code session:
/harness-init            # scaffolds .claude/project.md + settings hook + gitignore
/kickoff <plan> <handoff>   # reads the descriptor, stands up a right-sized fleet
```

`/kickoff` reads `.claude/project.md`, picks the `roster_profile` (solo/small/full), drops roles
whose descriptor inputs are absent (no UI ⇒ no designer/fe-dev; `deploy_targets: none` ⇒ no
deployer), applies the descriptor's `check_cmd`/`test_cmd`/`definition_of_done` gates, and emits a
ready-to-paste launch block per role terminal. A one-person POC gets a solo builder+reviewer; a large
multi-surface product gets the full PDT+Dev fleet.

## The descriptor

See [`schema/project.md`](schema/project.md). It's the one file that differs per project — stack,
gates, DoD, deploy targets, acceptance driver, product context, sources of truth, roster profile.
Everything else is shared.
