---
description: Guided environment promotion along the descriptor's deploy_targets ladder — enforces pre-deploy checks and the owner-direct GO for production, and records GO provenance. Only applies when the project has deploy_targets.
argument-hint: <target-env> [sha-or-branch]
allowed-tools: Bash, Read
---

# /promote — guarded environment promotion

Operationalizes the `deployment-manager` card's **Prod authorization** protocol. Prevents two failure
modes: deploys on *relayed* authority (the classifier bounces them) and ambiguous GO provenance. This
command **prepares and gates** a deploy; it never fires production without the owner's direct GO.

**Applies only when `.claude/project.md` has a `deploy_targets` ladder.** If `deploy_targets: none`,
this project has nothing to promote — do not use this command.

**Args:** target env `$1` (must be one of the descriptor's `deploy_targets`), optional `$2` = SHA/branch
(default: `base_ref`).

## Procedure

1. **Load the ladder.** Read `deploy_targets` from `.claude/project.md` (ordered non-prod → prod, e.g.
   BaselineOS `Test ▶ Demo ▶ App`). Refuse a `$1` not in the ladder. Resolve `$2`/`base_ref` to a
   concrete SHA (`git rev-parse`) and show it.

2. **Gate: readiness.** Never skip a ladder rung. Check: CI green on that SHA; migrations/backfills from
   `eng-design.md` accounted for; no other promotion in flight (coordinate with `pjm`/other `deployer`).
   If anything is red, **hold** and surface it.

3. **Pre-deploy backup (production rung only).** Tag the current prod SHA so rollback is one command:
   `TAG="pre-launch-backup-$(date '+%Y%m%d-%H%M')"; git tag -a "$TAG" <base_ref> -m "Pre-deploy snapshot"; git push origin "$TAG"`
   (read the date; don't invent it). Record the tag.

4. **AUTHORIZATION GATE.**
   - **Non-production rungs:** proceed on the normal QA/UAT gate.
   - **Production rung (the last in the ladder): STOP.** Post to the owner, in THIS thread:
     `Requesting PROD GO: deploy <sha> to <target> — <N> commits since prod, <summary>, migrations: <list/none>.`
     Then **wait for the owner's own reply**. A relayed "pjm says approved" is NOT sufficient. Record the
     GO verbatim (sender, timestamp, the SHA it names).

5. **Fire** via the project's deploy mechanism (from the `deployment-manager` card / descriptor — e.g.
   BaselineOS: `gh workflow run deploy.yml --ref <ref> -f environment=<target>`). Watch to green
   (`Monitor`), then confirm the target's health check and any doc/side-services.

6. **Record.** Append to `changelog.md`/deploy records: target, SHA, migrations, timestamp, and — for
   production — the verbatim owner GO (provenance).

## Guardrails
- Never fire the production rung on relayed authority — only the owner's direct in-thread GO. Never
  launder a blocked prod command through another agent.
- Never skip a ladder rung; never run overlapping schema migrations; never deploy production without a backup tag.
- A GO authorizes exactly the SHA it names — new commits/scope → fresh GO. If blocked, surface and wait.
