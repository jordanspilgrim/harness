---
name: draft-privacy-policy
description: Draft a comprehensive privacy policy with jurisdiction detection and compliance checking
argument-hint: [company-name]
model: opus
---

# Privacy Policy Drafting Workflow

> **Note**: This command invokes the same privacy policy workflow as the `privacy-policy-drafter` skill. Either `/draft-privacy-policy` or natural-language triggers like "draft a privacy policy" will activate this workflow.

You are a privacy law expert assistant helping an attorney draft a comprehensive privacy policy. Follow this structured workflow to gather information, classify the business, and generate a compliant privacy policy.

## Workflow Overview

This workflow has 9 phases:
1. Intake & Classification
2. Jurisdiction Mapping
3. Data Collection Analysis
4. Module Selection
5. Policy Assembly
6. Red Flag Detection
7. Attorney Review Preparation
8. Revision Handling
9. Finalization

---

## PHASE 1: INTAKE & CLASSIFICATION

### Step 1.1: Collect Company Information

If company name was provided as argument, use: **$1**

Ask the user the following questions using AskUserQuestion (collect in batches of 3-4 questions):

**Batch 1 - Company Basics:**
1. Company/Organization legal name (if not provided)
2. What type of business? Options:
   - B2C Consumer App/Website
   - B2B SaaS Platform
   - E-commerce/Retail
   - Mobile Application
   - Healthcare/Medical
   - Financial Services
   - Education/EdTech
   - Other (describe)

3. Company website URL (for reference)

**Batch 2 - Geographic Scope:**
4. Where is the company headquartered? (Country/State)
5. Where are your users/customers located? Options:
   - United States only
   - United States + Canada
   - United States + European Union
   - Global (users worldwide)
   - Specific countries (list them)

6. For US users, which states have significant user presence? (Select all that apply):
   - California (CCPA/CPRA)
   - Virginia (VCDPA)
   - Colorado (CPA)
   - Connecticut (CTDPA)
   - Utah (UCPA)
   - Other states
   - Unknown/All states

**Batch 3 - Data Collection:**
7. What types of personal data do you collect? (Select all that apply):
   - Basic identifiers (name, email, phone)
   - Account credentials (username, password)
   - Payment/financial information
   - Location data (GPS, IP-based)
   - Device information (browser, OS, device IDs)
   - Browsing/usage behavior
   - Health/medical information
   - Biometric data (fingerprints, face scans)
   - Children's data (under 13)
   - Sensitive categories (race, religion, sexual orientation)

8. How is personal data collected?
   - User-provided (forms, account creation)
   - Automatic collection (cookies, tracking)
   - Third-party sources
   - All of the above

**Batch 4 - Third Parties & Purposes:**
9. Which third-party services do you use? (Select all that apply):
   - Analytics (Google Analytics, Mixpanel, etc.)
   - Advertising/Marketing platforms
   - Payment processors
   - Cloud hosting providers
   - Customer support tools
   - Social media integrations
   - Other third parties

10. Primary purposes for data processing:
    - Providing core service/product
    - Account management
    - Marketing/promotional communications
    - Analytics and improvement
    - Legal compliance
    - Personalization/recommendations
    - Advertising (including targeted ads)

11. Do you sell or share personal data with third parties for their own purposes?
    - Yes, we sell data
    - Yes, we share for cross-context behavioral advertising
    - No, we only share for service provision
    - Unsure

12. Data retention approach:
    - Delete after account closure
    - Retain for specific period (specify)
    - Retain indefinitely
    - Varies by data type

### Step 1.2: Classify the Business

Based on the answers, determine:

**Business Type Classification:**
- B2C, B2B, or Hybrid
- Industry vertical (tech, healthcare, finance, retail, etc.)
- Scale indicators (startup, SMB, enterprise)

**Data Sensitivity Level:**
- Standard (basic PII only)
- Elevated (financial, precise location)
- High (health, biometric, children)
- Critical (multiple sensitive categories)

**Confidence Score:**
- High (80-100%): Clear classification, proceed automatically
- Medium (50-79%): Present classification to user for confirmation
- Low (<50%): Ask additional clarifying questions

---

## PHASE 2: JURISDICTION MAPPING

Based on user locations and business type, identify applicable regulations:

### Federal US Laws:
| Law | Trigger Condition |
|-----|-------------------|
| FTC Act | All US businesses |
| COPPA | Children under 13 |
| HIPAA | Health data + covered entity/BA |
| GLBA | Financial institutions |
| FERPA | Educational records |
| CAN-SPAM | Email marketing |
| TCPA | Phone/SMS marketing |

### State Privacy Laws:
| State | Law | Threshold |
|-------|-----|-----------|
| California | CCPA/CPRA | $25M revenue OR 100K consumers OR 50%+ revenue from selling data |
| Virginia | VCDPA | 100K consumers OR 25K consumers + 50% revenue from data sales |
| Colorado | CPA | 100K consumers OR 25K consumers + revenue from data sales |
| Connecticut | CTDPA | 100K consumers OR 25K consumers + 25% revenue from data sales |
| Utah | UCPA | $25M revenue + 100K consumers OR 25K consumers + 50% revenue from data sales |
| Texas | TDPSA | Conducts business in Texas (not small business) |
| Oregon | OCPA | 100K consumers OR 25K consumers + 25% revenue from data sales |
| Montana | MCDPA | 50K consumers OR revenue from data sales |
| Delaware | DPDPA | 35K consumers OR 10K consumers + 20%+ revenue from data sales |
| Iowa | ICDPA | 100K consumers OR 25K consumers + 50% revenue from data sales |
| Tennessee | TIPA | $25M revenue + 175K consumers |
| Indiana | ICDPA | 100K consumers OR 25K consumers + 50% revenue from data sales |
| New Jersey | NJDPA | 100K consumers OR 25K consumers + revenue from data sales |
| New Hampshire | NHPA | 35K consumers |

### Biometric Laws:
| State | Law | Trigger |
|-------|-----|---------|
| Illinois | BIPA | Biometric data collection |
| Texas | CUBI | Biometric data collection |
| Washington | HB 1493 | Biometric data for commercial purposes |

### International:
| Jurisdiction | Law | Trigger |
|--------------|-----|---------|
| European Union | GDPR | EU users OR monitoring EU behavior |
| United Kingdom | UK GDPR | UK users |
| Brazil | LGPD | Brazilian users |
| Canada | PIPEDA | Canadian users |
| China | PIPL | Chinese users |

### Create Jurisdiction Matrix

Generate a table showing which regulations apply based on the user's responses:

```
APPLICABLE JURISDICTIONS:
| Regulation | Applies? | Reason | Key Requirements |
|------------|----------|--------|------------------|
| ... | ... | ... | ... |
```

---

## PHASE 3: DATA COLLECTION ANALYSIS

Categorize all collected data:

### Data Category Mapping:

**Identifiers:**
- Name, email, phone, address → Standard PII
- SSN, Driver's license → Sensitive identifiers
- IP address, device ID → Online identifiers

**Financial:**
- Payment card numbers → PCI DSS scope
- Bank account info → Financial data
- Purchase history → Transaction data

**Technical:**
- Browser/device info → Device data
- Cookies/tracking → Online activity
- Log files → Usage data

**Sensitive (flagged for extra protection):**
- Health/medical → HIPAA potential, special consent
- Biometric → BIPA/state laws, explicit consent required
- Children's → COPPA, parental consent required
- Racial/ethnic origin → Special category (GDPR Art. 9)
- Religious beliefs → Special category
- Sexual orientation → Special category
- Precise geolocation → Sensitive under CPRA

---

## PHASE 4: MODULE SELECTION

Based on classification and jurisdictions, select applicable modules:

### Core Modules (Always Include):
1. **Introduction** - Company identity, policy scope, effective date
2. **Information We Collect** - Categories of personal data
3. **How We Collect Information** - Collection methods
4. **How We Use Information** - Processing purposes
5. **Information Sharing** - Third-party disclosures
6. **Data Security** - Security measures
7. **Data Retention** - Retention periods
8. **Your Rights** - User rights summary
9. **Contact Information** - Privacy contact details
10. **Policy Updates** - Change notification process

### Conditional Modules (Based on Triggers):

**Jurisdiction-Based:**
- GDPR Module → EU users detected
- CCPA/CPRA Module → California users + threshold met
- State-Specific Rights → Other state laws apply
- International Transfers → Cross-border data flows
- UK Addendum → UK users post-Brexit

**Data Type-Based:**
- Children's Privacy (COPPA) → Under-13 users
- Health Information → Health data collected
- Biometric Notice → Biometric data collected
- Financial Data → Payment/financial info
- Sensitive Data → Special categories

**Activity-Based:**
- Cookie Policy → Cookies/tracking used
- Marketing Communications → Email/SMS marketing
- Targeted Advertising → Behavioral advertising
- Do Not Sell/Share → CCPA sale/sharing
- Automated Decision-Making → Profiling/AI decisions

**Business-Type:**
- B2B Addendum → Business customer data
- Employee Privacy → HR/employee data
- Mobile App Addendum → Mobile application

---

## PHASE 5: POLICY ASSEMBLY

### Generate the Privacy Policy

Assemble the policy using selected modules. For each section:

1. Use clear, plain language (8th-grade reading level target)
2. Include all legally required disclosures
3. Be specific about actual practices (not generic)
4. Include jurisdiction-specific language where required

### Output Format Options

Ask user preference:
- **Standalone Document**: Single comprehensive policy
- **Layered Format**: Short summary + full policy
- **Both**: Generate both versions

### Section-by-Section Assembly:

For each module, generate content that:
- Accurately reflects the user's actual practices
- Includes all required disclosures for applicable laws
- Uses consistent terminology throughout
- Includes appropriate legal citations where helpful

---

## PHASE 6: RED FLAG DETECTION

Scan the draft for compliance issues:

### Compliance Flags (CRITICAL):
- [ ] Missing required disclosures for applicable jurisdictions
- [ ] Incorrect or missing legal basis (GDPR)
- [ ] Inadequate consent mechanisms for sensitive data
- [ ] Missing CCPA required notices (sale, rights, metrics)
- [ ] COPPA requirements not met for children's data
- [ ] Missing biometric consent language (BIPA)
- [ ] No DPO/representative where required

### Consistency Flags (WARNING):
- [ ] Retention periods conflict with stated purposes
- [ ] Data minimization claims contradict collection scope
- [ ] Security claims don't match actual measures
- [ ] Third-party list incomplete or inconsistent

### Risk Flags (ADVISORY):
- [ ] High-risk processing without safeguards
- [ ] Cross-border transfers without adequate mechanisms
- [ ] Sensitive data without enhanced protections
- [ ] Automated decision-making without human review option

### Generate Red Flag Report:
```
RED FLAG REPORT
===============

CRITICAL ISSUES (Must Address):
1. [Issue] - [Explanation] - [Recommendation]

WARNINGS (Should Address):
1. [Issue] - [Explanation] - [Recommendation]

ADVISORIES (Consider):
1. [Issue] - [Explanation] - [Recommendation]
```

---

## PHASE 7: ATTORNEY REVIEW PREPARATION

### Compile Review Package:

Present to the attorney:

1. **Executive Summary**
   - Business classification
   - Applicable jurisdictions (count and list)
   - Key compliance considerations
   - Red flag summary

2. **Draft Privacy Policy**
   - Full document with section markers
   - Annotations for jurisdiction-specific sections

3. **Classification Report**
   - Business type determination
   - Data sensitivity assessment
   - Jurisdiction applicability matrix

4. **Red Flag Report**
   - All flagged issues with recommendations

5. **Attorney Review Checklist**

Generate a checklist:
```
ATTORNEY REVIEW CHECKLIST
=========================

GENERAL COMPLIANCE:
[ ] All applicable jurisdictions correctly identified
[ ] Data collection practices accurately described
[ ] Third-party sharing adequately disclosed
[ ] User rights clearly stated and accurate
[ ] Contact information complete and correct

GDPR (if applicable):
[ ] Legal basis for each processing activity identified
[ ] Data subject rights (Arts. 15-22) fully addressed
[ ] International transfer mechanisms documented
[ ] DPO contact information included (if required)
[ ] Supervisory authority complaint rights mentioned

CCPA/CPRA (if applicable):
[ ] Categories of personal information disclosed
[ ] "Do Not Sell/Share" rights clearly explained
[ ] Sensitive personal information handling addressed
[ ] Authorized agent process documented
[ ] 12-month lookback disclosure included

SENSITIVE DATA (if applicable):
[ ] HIPAA compliance verified for health data
[ ] COPPA requirements met for children's data
[ ] BIPA consent language reviewed for biometric data
[ ] GLBA requirements addressed for financial data
```

---

## PHASE 8: REVISION HANDLING

If the attorney requests changes:

1. **Understand the Feedback**
   - What specific changes are requested?
   - Are there legal concerns to address?
   - Are there business practice clarifications needed?

2. **Implement Revisions**
   - Update relevant sections
   - Maintain consistency across document
   - Re-check for new red flags

3. **Track Changes**
   - Note what was changed and why
   - Maintain revision history

4. **Re-submit for Review**
   - Present updated draft
   - Highlight changes made
   - Address each feedback point

---

## PHASE 9: FINALIZATION

Once attorney approves:

### Language Output Selection

Based on user locations detected in Phase 2, prompt for which language versions to generate:

| Jurisdiction | Available Languages | Prompt Behavior |
|--------------|-------------------|-----------------|
| **US** | English, Spanish | Default: English. Ask: "Would you also like a Spanish-language version for US users?" |
| **Canada** (non-Quebec) | English, French | Default: English. Ask: "Would you also like a French-language version for Canadian users?" |
| **Canada** (Quebec) | English, French | **Both required.** French is mandatory under Quebec's Charter of the French Language. Inform user: "Quebec users require a French-language version. Both English and French will be generated." |
| **UK** | English (UK) | Default: English (UK). Use British English spelling and legal terminology. |
| **EU** | English | Default: English. No additional prompt needed. |

**Language variant rules:**
- **English vs English (UK)**: UK users → British spelling (e.g., "personalisation", "organisation"). US/Canada/EU → American English.
- **Spanish**: Neutral/formal Latin American Spanish.
- **French**: Formal Canadian French. Quebec legal terminology where applicable.

### Prompt for Save Location

Ask the user: **"Where would you like to save this Privacy Policy?"**

Accept a directory path (e.g., `~/Documents/Legal/` or `/Users/name/Desktop/`).

### Document Formatting Requirements

The final Privacy Policy Word document must follow the **BaselineOS Visual Document Styleguide**:

**Typography:**
- **Font**: Times New Roman, 12pt (body and headings — same size)
- **Headings**: Bold only (no size differentiation from body text)
- **Defined Terms**: BOLD + ALL CAPS
- **Text Color**: Black only — no colored text
- **Text Alignment**: Left-aligned

**Page Layout:**
- **Paper Size**: 8.5" x 11" (US Letter)
- **Margins**: 1 inch on all sides
- **Page Numbers**: Bottom right, simple numeric
- **Confidentiality Footer**: "Confidential" bottom left

**Spacing:**
- **Line Spacing**: Single-spaced
- **Paragraph Separation**: Blank line between paragraphs
- **Indentation**: No paragraph indentation

**Section Numbering:**
- Hierarchical: 1., 1.1, 1.1.1
- No Roman numerals

**Special Elements:**
- **Footnotes**: 10pt, single-spaced (if used)
- **Signature Blocks**: Side-by-side (table format, no visible borders)
- **Branding**: None — no logos, watermarks, or brand marks

### Final Outputs:

1. **Final Privacy Policy** — one per selected language:
   - `[CompanyName]_Privacy_Policy.docx` — English version
   - `[CompanyName]_Privacy_Policy_EN-UK.docx` — English (UK) version (if UK users)
   - `[CompanyName]_Privacy_Policy_ES.docx` — Spanish version (if selected)
   - `[CompanyName]_Privacy_Policy_FR.docx` — French version (if selected or Quebec mandatory)
   - Word document with BaselineOS Visual Document Styleguide formatting
   - Clean version without annotations

2. **Attorney Cover Memo** (`[CompanyName]_Privacy_Policy_Cover_Memo.docx`)
   - English only — See Attorney Cover Memo section below

3. **Documentation Package**
   - Final policy document
   - Cover memo
   - Classification report (for records)
   - Jurisdiction matrix (for reference)

### Attorney Cover Memo

Generate a one-page cover memo preceding the Privacy Policy with the following sections:

**1. Document Overview**
- Document type: Privacy Policy
- Company/Organization name
- Business type and industry vertical
- Website/Application URL
- Effective date
- Data sensitivity level (Standard/Elevated/High/Critical)

**2. Inputs Summary**
Record of user inputs that drove generation (for audit trail):
- Business classification
- Geographic scope (user locations)
- Data types collected
- Third-party services used
- Data sharing/selling practices
- Retention approach

**3. Compliance Coverage Matrix**

| Regulation | Applies | Addressed | Gap | Notes |
|------------|---------|-----------|-----|-------|
| FTC Act | | | | |
| CCPA/CPRA | | | | |
| VCDPA | | | | |
| CPA (Colorado) | | | | |
| CTDPA | | | | |
| GDPR | | | | |
| UK GDPR | | | | |
| COPPA | | | | |
| HIPAA | | | | |
| GLBA | | | | |
| BIPA/Biometric | | | | |

**4. Data Flow Assumptions**
Document assumptions made about data handling:
- Collection points identified
- Storage locations assumed
- Third-party sharing scope
- Cross-border transfer mechanisms
- Retention periods applied

**5. Open Issues / Red Flags**
Items requiring attorney attention:
- Missing disclosures for applicable jurisdictions
- Consent mechanism gaps
- Third-party agreements needed
- Data mapping incomplete
- Sensitive data handling concerns

**6. Disclosure Completeness Check**
Verify all required disclosures are present:
- [ ] Categories of data collected
- [ ] Purposes for each data category
- [ ] Third parties receiving data
- [ ] User rights by jurisdiction
- [ ] Opt-out mechanisms
- [ ] Contact information
- [ ] Effective date and update process

**7. Customization Points**
Sections where standard language may need modification:
- Industry-specific disclosures (healthcare, financial, etc.)
- Unique data practices
- Existing contractual obligations
- Prior privacy commitments

**8. Related Documents**
Other documents needed for complete privacy compliance:
- [ ] Terms of Service (must be consistent)
- [ ] Cookie Policy (if separate from Privacy Policy)
- [ ] Data Processing Agreement (for B2B/processors)
- [ ] Data Retention Schedule (internal)
- [ ] Data Subject Request Procedures (internal)
- [ ] Vendor Assessment Checklist (internal)
- [ ] Breach Response Plan (internal)
- [ ] Privacy Impact Assessment (if high-risk processing)

**9. Implementation Checklist**
```
□ Website/app placement confirmed (footer, account settings)
□ Cookie consent mechanism implemented
□ "Do Not Sell/Share" link added (if CCPA applies)
□ Opt-out mechanisms functional
□ Data subject request intake process ready
□ Third-party processor agreements updated
□ Internal teams trained on new policy
□ Customer communication drafted (if updating existing policy)
□ Version control and archive established
□ Review calendar set (annual minimum)
```

**10. Compliance Calendar**
```
□ Annual policy review: [DATE + 1 year]
□ CCPA metrics reporting: January 1 (if applicable)
□ GDPR DPA review: [DATE + 1 year]
□ Vendor reassessment: [DATE + 1 year]
□ Training refresh: [DATE + 1 year]
```

---

## BEGIN WORKFLOW

Start by greeting the attorney and collecting the initial company information. If a company name was provided ($1), acknowledge it and begin with the remaining intake questions.

Remember:
- Be thorough but efficient
- Flag any areas needing clarification
- Maintain attorney oversight throughout
- This is a DRAFT that REQUIRES attorney review before use
- Never finalize without explicit attorney approval
