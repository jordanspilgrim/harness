# Artifact skeletons

Copy the relevant block into `.claude/plans/<feature>/<file>.md`. Only the owner writes it.
Every downstream reference cites REQ/UAT IDs, never restates content.

## product-spec.md — owner: ideator
```
# Product Spec — <feature>
## Problem  (user · job-to-be-done · pain · why now)
## Success metrics  (outcome metric + exact PostHog events/telemetry required)
## Requirements
- REQ-01 (P0): <atomic, testable statement>
## Non-goals
## Edge cases & failure modes  (empty/error/permission/tenancy/adversarial)
## Open questions  (resolve with Gaby — never assume)
```

## uat-tests.md — owner: ideator
```
# UAT — <feature>
## UAT-01  (covers REQ-01)
Preconditions: ...
Steps: 1) ... 2) ...            (executable per the descriptor acceptance)
Pass criterion: <single observable result>
```

## design-spec.md — owner: designer
```
# Design Spec — <feature>
## REQ → screen/flow map
## UX  (interaction model, hierarchy, states: default/loading/empty/error/permission/success)
## UI  (shadcn/Radix components, Tailwind tokens, responsive)  — flag any additions
## Accessibility  (AA contrast, focus order, keyboard, ARIA)
## Motion  (trigger · property · duration · easing; reduced-motion)
```

## eng-design.md — owner: architect
```
# Engineering Design — <feature>
## REQ → component/route/module map
## Data & schema  (Drizzle changes, migrations, backfills)  — scoped by activeOrgId
## API & AI  (routes, streaming, model-config roles, cost logging)
## Threat model  (auth/tenancy · sanitization · secrets · S3 · PII)  → security pass checklist
## Testing strategy  (Vitest / Playwright / UAT feasibility · metric events)
```

## execution-plan.md — owner: architect
```
# Execution Plan — <feature>
| Task | REQ | Lane (FE/BE) | Depends on | Notes |
```

## delivery-plan.md — owner: pjm
```
# Delivery Plan — <feature>
## Team size + justification
## Assignments  (dlb-name → tasks → branch/worktree)
## Sequence & gate schedule
```
