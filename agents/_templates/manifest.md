# Manifest — <feature-slug>

> Sole writer: `pjm`. Everyone reads this first on wake to reorient. If reality disagrees
> with the manifest, raise it to `pjm` — do not let threads drift.

**Feature:** <name> · **Status:** <ideation|design|architecture|pdt-signoff|build|review|qa|merged|uat|deploy|shipped>
**Current owner (ball):** <dlb-name> · **Updated:** <YYYY-MM-DD HH:MM> · **Branch/worktrees:** <...>

## Requirements (REQ) index
| ID | Priority | Summary | Owner lane | Status |
|----|----------|---------|-----------|--------|
| REQ-01 | P0 | ... | FE / BE | pending |

## Acceptance (UAT) index
| ID | Covers REQ | Summary | Result |
|----|-----------|---------|--------|
| UAT-01 | REQ-01 | ... | not-run |

## Artifacts
| Artifact | Owner | Path | State |
|----------|-------|------|-------|
| product-spec.md | ideator | plans/<feature>/product-spec.md | ✅/🚧/⬜ |
| uat-tests.md | ideator | ... | |
| design-spec.md | designer | ... | |
| eng-design.md | architect | ... | |
| execution-plan.md | architect | ... | |
| delivery-plan.md | pjm | ... | |

## Gate ledger
| Gate | Status | Report | Date |
|------|--------|--------|------|
| PDT sign-off | ⬜ | — | |
| Code review | ⬜ | review-notes.md | |
| QA (merge) | ⬜ | qa-report.md | |
| UAT (acceptance) | ⬜ | uat-report.md | |
| Deploy (per deploy_targets) | ⬜ | changelog.md | |

## Team roster (this feature)
| DLB name | Role | Lane / scope |
|----------|------|--------------|
| pjm | Program Manager | coordination |

## Access (from the descriptor's `access:`, checked at kickoff)
| Role | Required (MCP / connectors / tools / paths) | Verified | Gap |
|------|--------------------------------------------|----------|-----|
| pjm | none | ok <YYYY-MM-DD> | none |

> A role with a gap is not launched. A gap found mid-task goes here and under Open blockers; the
> role calls `set_status(name, session_token, "blocked", detail)`. Never close a gap by relaying the work through another role.

## Open blockers / escalations
- <none>
