---
description: Run QA/UAT tests across all BaselineOS legal workflow skills
argument-hint: [system-name-or-all]
model: opus
---

# QA/UAT Agent — BaselineOS Legal Workflow Testing

Systematic quality assurance agent that tests all installed BaselineOS skills for structural integrity, dependency availability, file reference validity, and end-to-end workflow readiness.

---

## Input

The argument specifies what to test:

- `all` or no argument — Test everything
- `cgs` — Test the CGS system: `contract-generator` router + shared core + every extension skill
- `hdgs` — Test the HDGS system: `hr-generator` router + shared core + every extension skill
- `cfs` — Test the CFS system: `form-company` router + shared core + scripts + every extension skill
- `mlps` — Test the MLPS system: `marketing` router + shared core + every extension skill
- `standalone` — Test skills not owned by any router (e.g., privacy-policy-drafter, consent, terms-of-service, playbook, design-legal-workflow, process-my-scans — enumerate the actual set)
- `deps` — Test dependencies only (python-docx, openpyxl, Tesseract, etc.)
- A specific skill name (e.g., `nda-generator`) — Test that skill only

Derive each system's skill roster from its router's menu at run time — do not rely on a
remembered count. The rosters grow (dual-listed skills, new additions), and a hardcoded list
silently exempts the newest skills from QA, which is exactly where regressions live. "All"
means all: never sample or subset the roster without asking.

---

## Phase 1: Dependency Check

Run these checks first:

```bash
python3 -c "import docx; print('python-docx:', docx.__version__)"
python3 -c "import openpyxl; print('openpyxl:', openpyxl.__version__)"
which tesseract
python3 -c "import PIL; print('Pillow:', PIL.__version__)"
```

Report each as INSTALLED or NOT INSTALLED. Flag any NOT INSTALLED dependency as a potential runtime failure.

**Required dependencies:**
| Package | Required By | Impact if Missing |
|---------|-------------|-------------------|
| python-docx | ALL skills (50+) | All .docx generation fails |
| openpyxl | CFS cap_table_generator.py | CFS_05, CFS_07, CFS_08 cap tables fail |
| Tesseract | process-my-scans | Scan processing fails |
| Pillow | process-my-scans (edge cases) | Image processing may fail |

---

## Phase 2: Structural Validation

For each skill in scope, read the SKILL.md and check:

### 2.1 YAML Frontmatter
- [ ] `name` field present and matches directory name
- [ ] `description` field present
- [ ] `description` contains `MANDATORY TRIGGERS:` label (or equivalent trigger block)
- [ ] `version` field present (semver format X.Y.Z)

### 2.2 Shared Core References (for system skills only)
- [ ] Shared core file path is correct and file exists at that path
- [ ] Visual document styleguide file path is correct and file exists
- [ ] SKILL.md contains explicit "Read" or "Read and execute" instruction for the shared core

### 2.3 Output Generation
- [ ] Skill mentions `.docx` output format
- [ ] Skill mentions `python-docx` for document generation
- [ ] Skill specifies save location prompt or default output path
- [ ] Skill includes file naming convention

### 2.4 Attorney Review
- [ ] Attorney Review phase exists (unless skill is a Utility type)
- [ ] Attorney Review is marked as REQUIRED/MANDATORY/NEVER optional
- [ ] Review actions available (APPROVE, EDIT, FLAG, REJECT, or equivalent)

### 2.5 Cross-Reference Engine
- [ ] Companion document recommendations exist
- [ ] Cross-system references are present (where applicable)

### 2.6 ID Namespace
- [ ] Question IDs use a distinct prefix that doesn't collide with shared core IDs
- [ ] Module IDs use a distinct prefix
- [ ] Red flag IDs use a distinct prefix (if applicable)

---

## Phase 3: File Reference Validation

For each skill, extract all file paths referenced in SKILL.md and verify they exist:

```
~/.claude/skills/[name]/references/*.md
~/.claude/skills/[name]/scripts/*.py
~/.claude/skills/[name]/assets/*
~/.claude/skills/[router]/[core].reference.md
~/.claude/skills/[router]/visual-document-styleguide.reference.md
```

Report any referenced file that does not exist as a BUG.

---

## Phase 4: Python Script Validation

For each Python script found:

1. **Syntax check**: `python3 -c "import py_compile; py_compile.compile('[path]', doraise=True)"`
2. **Import check**: Extract all imports and verify required packages are installed
3. **Dead import check**: Identify imports that are not used in the code

---

## Phase 5: Router Validation

For each router skill (contract-generator, hr-generator, form-company, marketing):

1. **Menu completeness**: Every skill listed in the router menu exists as an installed skill
2. **Trigger consistency**: Router trigger commands match the extension skill triggers
3. **Path accuracy**: Skill paths listed in the router match actual installed paths
4. **Dual-listing accuracy**: Skills listed as dual-listed actually reference both systems' cores

---

## Phase 6: Cross-System Validation

Check cross-system references:

1. **CGS ↔ MLPS**: 4 dual-listed skills reference both contract-core and marketing-core
2. **HDGS → CGS**: Companion recommendations from HDGS skills correctly reference CGS skills
3. **CFS → CGS/HDGS**: CFS companion recommendations correctly reference other systems
4. **Visual Styleguide**: All systems point to a valid copy of the styleguide

---

## Phase 7: Content Completeness Check

For each skill, verify it doesn't defer critical phases to external sources (Notion, etc.):

- [ ] All workflow phases are embedded in the SKILL.md (not deferred to "See Notion")
- [ ] Red flag rules are embedded (not deferred)
- [ ] Attorney review checklist is embedded (not deferred)
- [ ] Negotiation positions are embedded (where applicable)

Flag any skill that defers phases to Notion as a CONTENT GAP.

---

## Phase 8: Test Scenarios

For each skill type, provide a fabricated test scenario that can be used for manual end-to-end testing:

### CGS Test Scenarios
| Skill | Test Scenario |
|-------|---------------|
| NDA | Mutual NDA between "TechVentures Inc." (Delaware C-Corp) and "DataFlow Ltd" (UK Ltd) for exploring a potential M&A transaction. Technology context with regulated data. |
| MSA | Professional services MSA between "CloudFirst Solutions" (California) and "Metro Health Systems" (New York) for IT consulting. Healthcare industry, HIPAA-sensitive. |
| Subscription | SaaS subscription agreement for "AnalyticsPro" platform. B2B enterprise customer "Global Retail Corp" with 500+ users. GDPR-relevant (EU subsidiary). |
| JDA | Joint development between "RoboTech Inc." (Massachusetts) and "AutoDrive GmbH" (Germany) for autonomous vehicle sensor technology. Complex IP allocation. |
| SRA | Sponsored research at MIT. Sponsor is "BioPharm Corp." Research on mRNA delivery mechanisms. Bayh-Dole framework. $2.5M over 3 years. |
| ICA | Intercompany shared services agreement between "HoldCo Inc." (US parent) and "HoldCo UK Ltd" (UK subsidiary). Transfer pricing for management fees. |
| Contract Review | Review a vendor MSA received from a counterparty. Upload a sample contract and run Mode A (counterparty review). |

### HDGS Test Scenarios
| Skill | Test Scenario |
|-------|---------------|
| Offer Letter | Senior Software Engineer offer at "TechStartup Inc." in California. $185K salary, 0.5% equity (ISO), 4-year vest with 1-year cliff. Remote-first. |
| IC Agreement | Independent contractor engagement for "MarketingAgency LLC" hiring a freelance graphic designer in New York. 6-month SOW, $150/hr. |
| Separation | Separating VP of Sales (age 52) at "SalesForce Solutions" in Illinois. 12 months severance, non-compete modification, OWBPA compliance. |
| PIIA | New hire PIIA for "AI Innovations Corp" in Massachusetts. Machine learning engineer with prior inventions from previous employer. |
| Arbitration | Mutual arbitration agreement for "FastGrow Startup" in California. 200 employees, class waiver included. |
| Performance Docs | PIP for underperforming marketing manager at "BigCorp" in Texas. 60-day improvement period, 3 measurable goals. |
| Comp Agreement | Commission plan for sales team at "SaaS Sales Co." in New York. Tiered structure with quarterly accelerators and annual clawback. |
| Leave/Accommodation | FMLA designation for employee at "Manufacturing Co." in Ohio. Serious health condition, 12 weeks requested. ADA interactive process. |
| Termination Letter | Involuntary termination (no severance) for employee at "RetailCorp" in Florida. Performance-based, at-will. Final pay + COBRA notice. |
| Workplace Policy | Remote work agreement for "DistributedTech" employees in California and New York. BYOD component, expense reimbursement, monitoring disclosure. |

### CFS Test Scenarios
| Skill | Test Scenario |
|-------|---------------|
| Entity Selection | New SaaS startup, 2 founders, planning to raise VC. Choosing between Delaware C-Corp and LLC. |
| Formation Documents | Delaware C-Corp formation for "InnovateTech Inc." 10M authorized shares. |
| Governance | Bylaws for "InnovateTech Inc." Standard VC-friendly governance. |
| Org Actions | Initial board resolutions for newly formed "InnovateTech Inc." Appoint officers, adopt bylaws, authorize share issuance. |
| Founder Equity | 2-founder RSPA split (60/40). 4-year vesting, 1-year cliff. 83(b) elections. IP assignment from both founders. |
| Shareholder Governance | Stockholders' agreement for "InnovateTech Inc." with 2 founders + 1 angel investor. ROFR, drag-along, tag-along. |
| Equity Comp | Equity Incentive Plan for "InnovateTech Inc." 10% option pool, ISO + NSO, standard vesting. |
| Convertible Instruments | Post-Money SAFE for "InnovateTech Inc." $500K investment at $10M cap. |
| Board Committees | Audit committee charter for "GrowthCo Inc." (Series B stage). 3 members, SOX-lite. |
| Annual Compliance | Annual board consent and compliance tracker for "InnovateTech Inc." Delaware, Year 1. |
| Charter Amendments | Amend certificate of incorporation for "InnovateTech Inc." to increase authorized shares from 10M to 20M (Series A prep). |
| Dissolution | Voluntary dissolution of "FailedStartup Inc." (Delaware C-Corp). No creditors, simple asset distribution. |

### MLPS Test Scenarios
| Skill | Test Scenario |
|-------|---------------|
| Ad Claims Review | Review "50% more effective than leading competitors" health supplement claim for US multi-channel campaign. |
| Sweepstakes Rules | Instagram photo contest for "FashionBrand" with $5,000 prize pool. Open to US + Canada. UGC component. |
| Influencer Agreement | 3-month campaign with lifestyle influencer (500K followers) for "BeautyCo." Instagram + TikTok. $15K + commission. |
| Marketing IP Release | Photo/video release for marketing shoot. 10 models, usage across digital + print. Perpetual license. |
| Direct Marketing | Email + SMS marketing compliance review for "E-CommerceCo" launching holiday campaign. US + EU audiences. |
| Sponsorship | "TechCorp" sponsoring annual developer conference. Naming rights for main stage. $250K sponsorship. |
| Co-Marketing | Joint marketing campaign between "BrandA" and "BrandB" for co-branded product launch. 6-month campaign. |
| Affiliate Terms | Affiliate program for "SaaS Platform" with tiered commissions (10-20%). US + international affiliates. |
| AI Marketing | AI-generated social media ad copy for "RetailBrand." GPT-4 generated, human-edited. Multi-platform. |
| Comparative Ads | "Our product is 3x faster than CompetitorX" claim in B2B SaaS context. Substantiation available. |
| UGC Compliance | Hashtag campaign #MyBrandStory for "LifestyleBrand." User photos + videos. Moderation + rights acquisition. |
| Social Media Policy | Corporate social media policy for "TechCorp" (500 employees). Employee personal use + brand ambassador program. |
| Collateral Review | Review existing website and marketing materials for "FinTechStartup" launching in US + UK. |

### Standalone Test Scenarios
| Skill | Test Scenario |
|-------|---------------|
| Privacy Policy | SaaS platform collecting PII, processing payments, using analytics. US + EU (GDPR) + California (CCPA). |
| Consent | Cookie consent banner for e-commerce site. US + EU + UK. Analytics + marketing cookies. |
| Terms of Service | B2C mobile app terms. In-app purchases, UGC, API access. US primary, UK secondary. |
| Playbook | Marketing domain playbook for "GrowthStartup" (Series A, 50 employees, SaaS, US + EU market). |

---

## Phase 9: Report Generation

Compile all findings into a report saved at:
`~/Documents/ClaudeCode/Outputs/QA_UAT_Report_[Date].md`

Use this format:
```
# BaselineOS POC — QA/UAT Report
Date: [date]
Scope: [what was tested]

## Executive Summary
[Bug count, UX issue count, warning count, pass count]

## CRITICAL BUGS
[Numbered list with system, skill, impact, fix]

## UX ISSUES
[Numbered list]

## WARNINGS
[Table]

## SYSTEM-BY-SYSTEM PASS MATRIX
[Tables per system]

## DEPENDENCY STATUS
[Table]

## DEMO RECOMMENDATIONS
[Prioritized fix list + safe workflows]
```

---

## Notes

- This command is a QA harness — it reviews skills statically (code review) and prepares test scenarios
- To run an actual end-to-end test of a skill, invoke the skill directly with the test scenario from Phase 8
- The command does NOT modify any skills — it only reads and reports
- Run with `all` before any demo to catch regressions
- Compare against the most recent prior `QA_UAT_Report_*.md` in `~/Documents/ClaudeCode/Outputs/` — new findings vs. carried-over findings is the signal a reader wants
