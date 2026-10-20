# harness

**This is the way I build software with Claude Code. Not the only way, but the one that works for me, and the one that shipped BaselineOS and Keel.**

harness is a project-agnostic agent fleet: install it once into `~/.claude`, and every repo gets a full software team: specialized agents, coordination commands, and lifecycle hooks. What changes per project lives in one committed file, `.claude/project.md`. Everything else is shared.

It was not designed in the abstract. It came out of building real products: first BaselineOS (a Next.js legal-workflow SaaS), then generalized when a standalone Python project (Keel) needed the same fleet without the BaselineOS stack or history.

## Why

Multi-agent dev works. Wiring it up per project does not: it is repetitive, and easy to get wrong. So harness makes the fleet reusable. The roles, the protocol, and the hooks are written once and installed globally. Each project declares only what is its own (stack, tests, definition of done, deploy targets) in a single descriptor. Start a session, run one command, and a right-sized team stands up.

Most orchestrators stop at the coordination: they run parallel agents and leave you to define what each one knows. harness is the other half. It ships the specialists (12 roles and a shared protocol), and drops the ones a given project does not need. That is the part that works for me.

## What you get

Roles (`agents/`), a card each, plus one shared protocol (teams, lifecycle, a single-writer artifact contract, traceability, model & effort tiers):

> ideator, architect, designer, program-manager, frontend-dev, backend-dev, code-reviewer, qa-tester, uat-tester, deployment-manager, bug-fixer, documenter

Commands (`commands/`):

- `/harness-init`: scaffolds a new project's descriptor, settings hook, and gitignore
- `/kickoff`: reads the descriptor and stands up a right-sized fleet
- `/standup`: checks fleet liveness
- `/promote`: runs a deploy-gated promotion
- everyday commands: build-skill, qa-test, deploy, draft-privacy-policy, and profile wrappers

Hooks (`hooks/`):

- `dlb-autoregister.sh`: registers each session's role and titles the session on start
- `dlb-monitor-supervised.sh`: a self-healing wake source
- `block-branch-switch.sh`: worktree isolation, wired per project when you turn it on

Skills (`skills/`), the methods a fleet applies rather than the roles that apply them:

- `blind-review-pass`: run a review as a measurement, not an opinion. Pre-registered exit bar and
  prediction, the prior findings physically removed from the search space, refute-by-default
  verification where nulls count against the bar, mirror-image attacks on every gate, and
  recall/precision/net-new reported as numbers. Written after a 17-pass loop hit its floor.

## Layout

```
agents/       role cards + the shared protocol (agents/README.md) + _templates/
commands/     kickoff, standup, promote, harness-init, and everyday commands
hooks/        DLB autoregister, supervised monitor, branch-switch guard
skills/       methods the fleet applies (blind-review-pass), one dir per skill
schema/       project.md: the descriptor spec, a starter template, worked examples
install.sh    symlink agents/ commands/ hooks/ skills/ into ~/.claude (idempotent)
bootstrap.sh  refresh this checkout (git pull --ff-only), then reinstall
templates/    project-bootstrap.sh: the self-contained per-project installer
```

## Requirements

- Claude Code
- DLB as an MCP server: `uv tool install dlb-mcp`, then configure the `dlb` server
- `uv` for Python tooling

## Install

```bash
git clone https://github.com/jordanspilgrim/harness.git ~/ClaudeCode/harness
~/ClaudeCode/harness/install.sh   # symlinks agents/ commands/ hooks/ into ~/.claude
```

The installer prints the exact `dlb-autoregister` SessionStart block to add to `~/.claude/settings.json`.

For outcome protection, wire `git-post-checkout-guard.sh` into each project's Git
`post-checkout` hook. For Husky, add this line to `.husky/post-checkout`:

```sh
[ ! -f "$HOME/.claude/hooks/git-post-checkout-guard.sh" ] || bash "$HOME/.claude/hooks/git-post-checkout-guard.sh" "$@"
```

It runs only with `CLAUDECODE=1`, only after branch checkouts in the primary
worktree. It restores the primary branch without forcing dirty changes and alerts
on stderr and in `~/.claude/harness-alerts.log`. Secondary worktrees and human
terminal checkouts are unaffected. The primary branch defaults to `origin/HEAD`,
then `init.defaultBranch`, then an existing `main` or `master`; set
`git config harness.primaryBranch <branch>` for an explicit choice. An unresolved
or missing primary branch alerts without attempting recovery. This complements
the PreToolUse check, including its best-effort directory-option parsing.

Refresh an existing checkout and reinstall in one step:

```bash
~/ClaudeCode/harness/bootstrap.sh
```

## Use it in a project

```bash
cd ~/ClaudeCode/my-project
# in a Claude Code session:
/harness-init                 # scaffolds .claude/project.md + settings hook + gitignore
/kickoff <plan> <handoff>     # reads the descriptor, stands up a right-sized fleet
```

What does `/kickoff` actually do? It reads `.claude/project.md`, picks the roster profile (solo, small, or full), and drops roles whose inputs are missing (no UI, so no designer or frontend-dev; `deploy_targets: none`, so no deployer). It applies the descriptor's check, test, and done gates, and prints a ready-to-paste launch block per role. A one-person POC gets a builder and a reviewer. A big multi-surface product gets the full team.

### Per-project bootstrap

`/harness-init` drops `scripts/harness-bootstrap.sh` into the project (a copy of `templates/project-bootstrap.sh`). It is self-contained: it clones or fast-forwards harness into `~/ClaudeCode/harness`, then runs `install.sh`. So anyone who clones a harness-using repo gets the fleet with one command: `npm run bootstrap`, `make bootstrap`, or `./scripts/harness-bootstrap.sh`. Override the location or URL with `HARNESS_DIR` and `HARNESS_URL`.

## The descriptor

`schema/project.md` is the one file that changes per project: stack, gates, definition of done, deploy targets, acceptance driver, product context, sources of truth, roster profile. Everything else is shared. One file per project. That is the whole idea.

## License

MIT. See [LICENSE](LICENSE).
