---
name: build-skill
description: Build an installable BaselineOS skill from a completed workflow specification
argument-hint: [spec-file-path-or-notion-page-id]
model: opus
---

# Build Skill

Compiler/translator that takes a completed workflow specification and produces an installed, functional BaselineOS skill.

This command does NOT re-do design work. If the spec has gaps, it flags them and asks for resolution — it does not invent missing content.

---

## Phase 1 — Spec Intake

### 1.1 Read the Spec

The argument tells you where the spec lives: a path ending in `.md` → read the file in full; a
UUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` or 32 hex chars) → fetch the page via the Notion
API; empty → ask the user for a file path, Notion page ID, or pasted content.

### 1.2 Extract Metadata

Parse the spec to extract:

| Field | Where to Find |
|-------|--------------|
| Skill name | Title or Executive Summary |
| Trigger command | Infer from name (e.g., `vendor-due-diligence` → `/vdd`) |
| Category | Quick Links or Executive Summary |
| Architecture type | Build-Skill Handoff block or Workflow Overview |
| Document style | Build-Skill Handoff block or Output Package section |
| Jurisdictions | Jurisdiction & Language Protocol section |
| Question prefix | First question ID (e.g., `VDD-001` → prefix is `VDD`) |
| Module prefix | First module ID (e.g., `VDD-M01` → prefix is `VDD`) |
| Red flag model | Red Flag Rules section (count tiers to determine model) |
| Red flag count | Count of red flag rules |
| Question count | Statistics Summary or count from question tables |
| Module count | Statistics Summary or count from module tables |
| Output package | Output Package section or Finalization phase |
| Helper script needs | Build-Skill Handoff block or §5.9 assessment |
| Reference file needs | Build-Skill Handoff block or §5.9 assessment |
| Asset needs | Build-Skill Handoff block |
| Shared core refs | Build-Skill Handoff block (§ numbers or "none") |

### 1.3 Display & Confirm

Present extracted metadata to user:

```
EXTRACTED METADATA
──────────────────────────────────────
Skill name:       [name]
Trigger:          /[trigger]
Category:         [category]
Architecture:     [CGS Extension / Standalone / Hybrid / Utility]
Doc Style:        [Legal Agreements / Analyses & Reviews / Both / N/A]
Jurisdictions:    [list]
ID Prefix:        [PREFIX]
Red Flag Model:   [Standard / Review / Governance] ([count] rules)
Questions:        [count] ([core] core + [cond] conditional)
Modules:          [count] ([core] core + [cond] conditional)
Output Package:   [list of documents]
Shared Core:      [§ list or "none"]
Scripts Needed:   [list or "none"]
References Needed:[list or "none"]
Assets Needed:    [list or "none"]
──────────────────────────────────────
```

Confirm with user before proceeding. If any field cannot be extracted, flag it and ask the user.

---

## Phase 2 — Architecture Analysis

### 2.1 Build Strategy

Based on the architecture type, determine the build approach:

#### CGS Extension

- SKILL.md references shared core by path: `~/.claude/skills/contract-generator/contract-core.reference.md`
- SKILL.md references visual styleguide by path: `~/.claude/skills/contract-generator/visual-document-styleguide.reference.md`
- Phases that execute shared core sections specify: "Read and execute contract-core.reference.md §[N]"
- Does NOT duplicate shared core content — only references it
- Uses shared §6 Document Generation Protocol for output

**Shared Core Consumption Table** (include in SKILL.md):

| Section | Purpose | Usage |
|---------|---------|-------|
| §1 Shared Intake | CORE questions | Execute — ask CORE-001 through CORE-010 + conditionals |
| §2 Classification | Complexity tiers | Execute — classify across 4 dimensions |
| §3 Boilerplate Clauses | Standard modules | Execute — include applicable BP modules |
| §4 Jurisdiction Adaptation | Law-specific clauses | Execute — adapt per governing law |
| §5 Industry Overlays | Sector requirements | Execute — apply if CORE-009 triggers |
| §6 Output Generation | Document formatting | Execute — use python-docx helpers |
| §7 Cross-References | Companion contracts | Execute — recommend related contracts |
| §8 Version History | Core versioning | Reference only |

#### Standalone

- SKILL.md is fully self-contained
- All protocols embedded inline (intake, classification, jurisdiction, language, output)
- python-docx formatting helpers embedded or in a skill-local script
- References visual styleguide for formatting standards (embed the relevant family's rules)

#### Hybrid

- Generate a selective import table specifying exactly which §§ are consumed
- Sections NOT imported must have their equivalent embedded in SKILL.md
- Example (Contract Review): uses §3,§4,§5,§7,§8 but NOT §1,§2 (own intake) and NOT §6 (own output)

#### Utility

- No shared core references
- No legal ceremony (no attorney review, no cover memo unless spec says otherwise)
- Focus on operational phases: input → process → output

### 2.2 Identify Support Files

Based on the spec, list all files to generate:

```
FILES TO GENERATE:
1. ~/.claude/skills/[name]/SKILL.md           (always)
2. ~/.claude/skills/[name]/references/[x].md  (if reference files needed)
3. ~/.claude/skills/[name]/scripts/[x].py     (if Python scripts needed)
4. ~/.claude/skills/[name]/assets/[x]         (if asset files needed)
```

Confirm file list with user.

---

## Phase 3 — SKILL.md Generation

Generate the complete SKILL.md following this structure:

### 3.1 YAML Frontmatter

```yaml
---
name: [skill-name]
description: |
  [2-4 sentence description of what the skill does, when to use it, what it produces.]
  MANDATORY TRIGGERS: /[trigger], [natural language triggers from spec]
version: 1.0.0
---
```

**MANDATORY TRIGGERS rules:**
- Always include the slash command trigger first
- Include 8-15 natural language triggers
- Include common synonyms and abbreviations
- Include key terms from the spec's Executive Summary

### 3.2 Title & Overview

```markdown
# [Skill Name]

[1-2 sentence description matching the YAML description.]

## Overview

When this skill is activated, guide the user through a structured workflow to [purpose].
The workflow adapts dynamically based on:
- [Adaptation dimension 1]
- [Adaptation dimension 2]
- [Adaptation dimension 3]
```

### 3.3 Skill Metadata Block

```markdown
## Skill Metadata

- **Name**: [name]
- **Version**: 1.0.0
- **Category**: [category]
- **Trigger**: `/[trigger]`
- **Parent System**: [CGS / Standalone / etc.]
```

For CGS Extension, add:
```markdown
- **Shared Core**: Read `contract-core.reference.md` from `~/.claude/skills/contract-generator/contract-core.reference.md`
- **Visual Styleguide**: Read `visual-document-styleguide.reference.md` from `~/.claude/skills/contract-generator/visual-document-styleguide.reference.md`
```

### 3.4 Shared Core References (CGS/Hybrid only)

Include the consumption table from Phase 2. For Hybrid, mark each section as "Execute" / "Reference only" / "Not used — embedded below".

### 3.5 Deliverables Section

```markdown
## Deliverables

All deliverables are output as `.docx` files using the BaselineOS Visual Document Styleguide — **[Legal Agreements / Analyses & Reviews]** family. User is prompted for save location.

This skill produces:
1. **[Primary Document] (.docx)** — [description]
2. **Attorney Cover Memo (.docx)** — [description]
3. **Implementation Checklist (.docx)** — [description]
4. [Additional deliverables from spec]
```

### 3.6 Workflow Phases

Translate each phase from the spec into the SKILL.md format:

```markdown
## Instructions

When this skill is invoked, follow these phases sequentially. Do not skip phases.

### Phase [N]: [Name]

[Phase description from spec, translated into imperative instructions for the AI.]
```

**Translation rules:**
- Spec says "the workflow collects..." → SKILL.md says "Ask the user..."
- Spec says "the system classifies..." → SKILL.md says "Classify the input as..."
- Spec says "red flags are checked..." → SKILL.md says "Check for the following red flags..."
- Preserve every question, module, and red-flag table verbatim — IDs, options, conditions,
  severities, actions. The IDs are contract surface: QA validation, cross-references, and the
  attorney review flow all key off them, so a dropped, renamed, or paraphrased row is a silent
  functional regression that no build check will catch for you.

### 3.7 Question Tables

Preserve every question from the spec with exact IDs:

```markdown
#### Core Questions (Always Ask)

| ID | Question | Input Type | Options | Purpose |
|----|----------|------------|---------|---------|
| [PREFIX]-001 | [question] | [type] | [options] | [purpose] |
```

### 3.8 Module Library

Preserve every module from the spec with exact IDs:

```markdown
#### Core Modules (Always Include)

| ID | Module Name | What to Generate |
|----|-------------|-----------------|
| [PREFIX]-M01 | [name] | [description of what to produce] |
```

### 3.9 Red Flag Rules

Preserve every red flag from the spec:

```markdown
### Red Flag Rules

| ID | Severity | Category | Condition | Action |
|----|----------|----------|-----------|--------|
| [PREFIX]-RF01 | [level] | [category] | [condition] | [action] |

**Auto-Fix Protocol:** When a red flag has an auto-fix: (1) apply automatically, (2) log in Attorney Cover Memo, (3) attorney can override during review.
```

### 3.10 Attorney Review Section

Every skill with legal output includes this section — a generated legal document that reaches a
user without attorney review is a malpractice risk, so its absence is a build failure, not a
style choice. Only Utility-architecture skills (no legal output) omit it.

```markdown
### Phase [N]: Attorney Review [REQUIRED]

Present the generated document(s) to the attorney for review.

#### Review Interface
- Display the complete draft document
- Highlight all red flags and auto-fixes applied
- Present the Attorney Cover Memo

#### Review Actions
- **APPROVE**: Accept as-is, proceed to finalization
- **EDIT**: Modify specific sections (re-generate affected portions)
- **FLAG**: Add concern/note for follow-up
- **REJECT**: Major revision needed (return to questioning phase)
- **REQUEST INFO**: Need more information from user

Attorney review is MANDATORY. Do not skip or auto-approve.
```

### 3.11 Output Generation Section

#### For CGS Extension:
```markdown
### Phase [N]: Output Generation

**Read and execute** `contract-core.reference.md` §6:

1. Ask user for save location (default: `~/Documents/ClaudeCode/Outputs/`)
2. Determine language versions per Language Output Protocol in §6
3. Generate each document as `.docx` using the shared python-docx formatting helpers
4. Save with the file naming convention: `[PartyA]-[ContractType][-LanguageSuffix].docx`
5. Confirm files saved and list full file paths
```

#### For Standalone:
```markdown
### Phase [N]: Finalization & Output

1. Ask user: "Where would you like to save the output files?" (default: `~/Documents/ClaudeCode/Outputs/`)
2. Determine language versions:
   [embed Language Output Protocol from spec]
3. Generate all documents as `.docx`:
   [embed python-docx protocol or reference styleguide]
4. Save with naming convention: `[Name]-[DocumentType][-LanguageSuffix].docx`
5. Confirm files saved and list full file paths

#### Output Package
| Document | Format | Style Family |
|----------|--------|-------------|
| [Primary doc] | .docx | [Legal Agreements / Analyses & Reviews] |
| Attorney Cover Memo | .docx | Analyses & Reviews |
| Implementation Checklist | .docx | Analyses & Reviews |
```

### 3.12 Document Formatting Section

#### For Legal Agreements style:
```markdown
#### Document Formatting — Legal Agreements

Reference: `~/.claude/skills/contract-generator/visual-document-styleguide.reference.md`

Key rules:
- **Font**: Times New Roman, 12pt (body AND headings — same size)
- **Headings**: Bold only — no size differentiation
- **Defined Terms**: **BOLD + ALL CAPS** (e.g., **CONFIDENTIAL INFORMATION**)
- **Spacing**: Single-spaced, blank line between paragraphs, no indentation
- **Page Layout**: US Letter, 1" margins
- **Page Numbers**: Bottom right
- **Footer**: "Confidential" bottom left
- **Section Numbering**: 1. / 1.1 / 1.1.1 (no Roman numerals)
- **Signature Blocks**: Side-by-side table format (no visible borders)
- **Exhibits**: New page, centered, bold, ALL CAPS
- **Branding**: None — no logos, watermarks, or brand marks
- **Text Color**: Black only
```

#### For Analyses & Reviews style:
```markdown
#### Document Formatting — Analyses & Reviews

Reference: `~/.claude/skills/contract-generator/visual-document-styleguide.reference.md`

Key rules:
- **Font**: Work Sans, 11-12pt
- **Layout**: Card-like, modern spacing, high whitespace
- **Body Text Color**: #333333 (dark gray)
- **Heading Color**: #000000 (black)
- **Page Layout**: US Letter, 1" margins
- **Branding**: None
```

### 3.13 Statistics Summary

```markdown
## Statistics

| Metric | Count |
|--------|-------|
| Core Questions | [N] |
| Conditional Questions | [N] |
| Total Questions | [N] |
| Core Modules | [N] |
| Conditional Modules | [N] |
| Total Modules | [N] |
| Red Flag Rules | [N] |
| Workflow Phases | [N] |
| Jurisdictions | [list] |
| Output Documents | [N] |
```

### 3.14 Version History

```markdown
## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | [today's date] | Initial release. Built from [spec name]. |
```

---

## Phase 4 — Support File Generation

### 4.1 Reference Files

For each reference file identified in Phase 2:

- Create at `~/.claude/skills/[name]/references/[filename].md`
- Extract the relevant structured data from the spec
- Format as clean markdown tables or structured content

### 4.2 Python Helper Scripts

For each script identified in Phase 2:

- Create at `~/.claude/skills/[name]/scripts/[filename].py`
- Include:
  - Shebang line: `#!/usr/bin/env python3`
  - Module docstring describing purpose
  - `import argparse` with `--check-deps` flag
  - Function stubs with docstrings matching spec requirements
  - `if __name__ == "__main__":` block
- After writing, run `chmod +x` on the script

**Script stub template:**

```python
#!/usr/bin/env python3
"""[Script purpose from spec]."""

import argparse
import sys

def check_dependencies():
    """Verify required packages are installed."""
    required = []  # Add required packages
    missing = []
    for pkg in required:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print(f"Install with: pip install {' '.join(missing)}")
        sys.exit(1)
    print("All dependencies satisfied.")

# [Function stubs from spec]

def main():
    parser = argparse.ArgumentParser(description="[description]")
    parser.add_argument("--check-deps", action="store_true", help="Check dependencies")
    # [Add arguments from spec]
    args = parser.parse_args()

    if args.check_deps:
        check_dependencies()
        return

    # [Main logic]

if __name__ == "__main__":
    main()
```

### 4.3 Asset Files

For each asset identified in Phase 2:
- Create the directory `~/.claude/skills/[name]/assets/`
- Note: binary assets (templates, images) may need to be created separately

### 4.4 CGS Extension Note

For CGS Extensions: do NOT create local copies of shared core files. The SKILL.md references them by absolute path from the `contract-generator` skill directory.

---

## Phase 5 — Installation

### 5.1 Create Directory Structure

```
~/.claude/skills/[name]/
├── SKILL.md
├── references/          (if needed)
│   └── [reference files]
├── scripts/             (if needed)
│   └── [script files]
└── assets/              (if needed)
    └── [asset files]
```

### 5.2 Write All Files

Write SKILL.md and all support files to their locations.

### 5.3 Set Permissions

```bash
chmod +x ~/.claude/skills/[name]/scripts/*.py  # if scripts exist
```

### 5.4 Verify Skill Discovery

The skill should now appear in Claude Code's skill picker. Confirm by checking:
- `~/.claude/skills/[name]/SKILL.md` exists
- YAML frontmatter parses correctly
- MANDATORY TRIGGERS are present in the description

---

## Phase 6 — Verification

Run all verification checks and report results.

### 6.1 Structural Checks

```
STRUCTURAL:
[ ] SKILL.md exists at ~/.claude/skills/[name]/SKILL.md
[ ] YAML frontmatter present and valid
[ ] name field matches skill directory name
[ ] description field present and non-empty
[ ] MANDATORY TRIGGERS present in description
[ ] version field = 1.0.0
[ ] All referenced files exist (references/, scripts/, assets/)
```

### 6.2 Content Checks

```
CONTENT:
[ ] All spec phases represented in SKILL.md
[ ] All question IDs from spec present ([count] expected, [count] found)
[ ] All module IDs from spec present ([count] expected, [count] found)
[ ] All red flag IDs from spec present ([count] expected, [count] found)
[ ] Attorney Review section present (except Utility)
[ ] Output generation section present
[ ] Statistics summary matches spec
```

### 6.3 Architecture Checks

```
ARCHITECTURE:
[ ] CGS Extension: contract-core.reference.md path correct and file exists
[ ] CGS Extension: visual-document-styleguide.reference.md path correct and file exists
[ ] CGS Extension: consumption table present
[ ] Standalone: all protocols embedded (no dangling shared core refs)
[ ] Hybrid: import table present with Execute/Not used annotations
[ ] Utility: no unnecessary legal ceremony
```

### 6.4 Namespace Checks

```
NAMESPACE:
[ ] ID prefix does not collide with existing skills:
    Reserved: CORE- NDA- MSA- SUB- JDA- SRA- ICA- CR- PB- PP- TOS- CON- DLW-
             MKT- PDC- CMP- CTR- PDS- BP-
[ ] No duplicate question IDs within the skill
[ ] No duplicate module IDs within the skill
[ ] No duplicate red flag IDs within the skill
```

### 6.5 Report

Present the final installation report:

```
BUILD COMPLETE
──────────────────────────────────────
Skill:     [name]
Trigger:   /[trigger]
Location:  ~/.claude/skills/[name]/
Version:   1.0.0

Files Created:
  SKILL.md                    [line count] lines
  references/[file].md        [line count] lines  (if applicable)
  scripts/[file].py           [line count] lines  (if applicable)

Verification:
  Structural:  [PASS/FAIL] ([count]/[total])
  Content:     [PASS/FAIL] ([count]/[total])
  Architecture:[PASS/FAIL] ([count]/[total])
  Namespace:   [PASS/FAIL] ([count]/[total])

Statistics:
  Questions:   [count]
  Modules:     [count]
  Red Flags:   [count]
  Phases:      [count]

To invoke: /[trigger]
──────────────────────────────────────
```

If any checks fail, list the failures and ask the user whether to fix them or proceed as-is.

---

## Error Handling

### Spec Gaps

If the spec is missing required information:

1. **Missing architecture type** → Ask user: "What architecture type should this skill use? (CGS Extension / Standalone / Hybrid / Utility)"
2. **Missing jurisdiction protocol** → Ask user: "What jurisdictions should this skill cover? (US / Canada / UK / EU)"
3. **Missing red flags** → Warning: "The spec has no red flag rules. Should I proceed without them, or would you like to add some?"
4. **Missing output package** → Ask user: "What documents should this skill produce?"
5. **Missing question/module IDs** → Warning: "Questions/modules lack IDs. I'll assign [PREFIX]-NNN IDs. Confirm prefix: [PREFIX]"

### Build Failures

If file writing fails:
- Check directory permissions
- Verify path exists
- Report the specific error and ask user to resolve

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-10 | Initial release |
| 1.1.0 | 2026-07-24 | Opus 5 optimization: merged duplicate intake steps, rationale-based fidelity rules. Generated-skill templates unchanged (they target the product runtime models, not this command's model). |
