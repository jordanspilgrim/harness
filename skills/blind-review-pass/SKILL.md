---
name: blind-review-pass
description: Run an adversarial review pass as a measured experiment rather than an opinion — pre-registered exit bar and prediction, an answer key physically removed from the search space, refute-by-default verification where nulls count against the bar, and mirror-image attacks on every gate. Use when running or re-running a review/audit on code that has been reviewed before, when you need to know how much to trust a prior review, when a review→fix loop has stopped converging, or whenever someone asks for a "comprehensive", "adversarial", or "independent" review. Also use before building any gate, lint, or test grid intended to catch a recurring defect class.
---

# Blind review pass

A review is usually an opinion with a file path attached. This makes it a measurement.

The method exists because iterative review→fix loops stop converging: past some depth each pass's
remediation introduces roughly as much as it closes, and the loop is measuring the fixer, not the
code. You cannot tell you are there without instrumenting the review itself.

## When this applies

Use it when **any** of these hold:

- the code has been reviewed before, so "did we find everything?" is answerable;
- a prior review's verdict is load-bearing and you do not know its error bars;
- a review→fix loop has run several rounds and you suspect it has stopped converging;
- someone asks for a "comprehensive" or "independent" or "adversarial" review;
- you are about to build a gate (a test grid, an oracle, a lint, a completeness check) to catch a
  recurring defect class.

Skip it for a first-ever review of new code: there is no prior to measure against, so run a normal
review and pre-register the exit bar for next time.

---

## 1. Pre-register, in writing, before anything runs

Write the protocol, the exit bar, and a **falsifiable prediction** into a file before a single
reviewer starts. Then do not edit that section after results land.

- **Exit bar** — explicit severity thresholds *and* a count of unverified findings. Never narrow
  the bar to reach it; report "not met" instead.
- **Prediction** — where you expect findings, at what scale, and (if measuring a prior pass) the
  expected recall. Checking it afterwards is the only honest read on convergence.
- **A process-failure clause** that fires independently of severity counts. The one that earns its
  keep: *"a finding in a class that already has a gate → treat the mechanization as broken; stop
  and disclose."*

A prediction recorded afterwards is a story. Encode the bar as an assertion, not a comment.

**Whoever checks the prediction must report the half that was wrong.** That is what makes recording
it worth anything.

## 2. Isolate the answer key PHYSICALLY, not with instructions

**This is the step everyone gets wrong, and it fails silently.**

If you are measuring a blind pass against a prior review, the prior review's findings are an answer
key. Telling reviewers "do not open `FINDINGS.md`" is **not a control**. Agents search the repo by
reflex, and a single unfiltered `grep -r` returns the answer key's contents without anyone
"opening" anything. Findings files are especially dangerous because they often put a whole failure
scenario on one physical line: four matched lines can mean four *complete* findings, not fragments.

Before launch, in order of preference:

1. **Move the answer key out of the working tree entirely** (a sibling directory, a branch not
   checked out, a gist). Nothing in the search space, nothing to leak.
2. If it must stay, **mandate an exclusion on every search** and state it in the launch prompt, not
   just the protocol doc:
   ```
   git grep -n PATTERN -- . ':!path/to/handoff'
   grep -rn --exclude-dir=handoff PATTERN .
   ```
3. **Audit the always-loaded files.** `CLAUDE.md`, the project descriptor, and any auto-loaded
   context are read by every thread. If they summarise prior findings, those findings are leaked to
   everyone before work starts.

**When a leak is structural, do not delete the leaking text if it carries real safety value.**
A warning that stops threads trusting a broken gate is worth more than a tidy experiment. Declare
the leak, name exactly which findings it exposes, and **adjust the denominator** — measure recall
against the uncontaminated subset and say so.

## 3. Make declaring contamination cheap

Tell every reviewer, in the launch prompt:

> If you see the answer key, say so immediately. Declared contamination is recoverable; silent
> contamination is not. Nobody is penalised for reporting it.

A reviewer who fears being discarded will stay quiet, and one quiet reviewer invalidates the whole
measurement. Back the promise up: a contaminated thread's uncontaminated work still counts.

**Salvage pattern — two arms.** When one dimension gets contaminated, do not discard it. Relaunch
that dimension as a fresh blind thread carrying the measurement, and keep the contaminated thread
running as a *primed* arm with its priming frozen (it must not read any more). You get a comparison
you did not have: does a primed reviewer out-find a blind one, beyond simply being handed answers?
Require a per-finding `independence:` field (`CLEAN` / `PRE-LEAK` / `CONTAMINATED(<ref>)`) so
synthesis can filter mechanically instead of trusting prose. The arms must not communicate.

## 4. Attack every gate with the defect's mirror image

A gate is written by the same reasoning that shipped the defect, so it inherits the same blind spot.
A green gate is not evidence until you have attacked the gate itself.

For each gate:

1. Write the **inverse** of the defect it catches, not a variant — leading token ↔ trailing token,
   upper ↔ lower, present ↔ absent — and confirm the gate fails. If it passes, that is a finding.
2. Enumerate the gate's own axes and check none is **pinned**. A grid with a constant is a line.
3. Answer concretely, in writing: *what would this gate still not see?*
4. A completeness check deriving its expectation from the source it checks is **circular by
   construction** — a finding on sight.
5. Enumerate gates **from source**, never from a doc list. A list harvested from docs both
   contaminates the reviewer and inherits the blind spot the exercise exists to break.

Treat a finding in a class that already has a gate as *"the gate is broken"* first and *"a new bug"*
second. Fix the gate first, or the class returns.

## 5. Verify by refutation, and count nulls against the bar

Verification is a separate stage run by a separate thread, instructed to **refute by default** and
to reproduce each claimed failure itself rather than trusting the reporter's reproduction.

Verdicts are `CONFIRMED`, `REFUTED`, or `UNVERIFIED`. **A null or inconclusive result is
UNVERIFIED and counts against the exit bar.** Bucketing nulls as "refuted" turns unchecked findings
into a clean report and invalidates the pass.

Do not weaken the verification prompt between passes. If intensity drops, the comparison is
meaningless — diff the prompts and show it did not.

## 6. Synthesise into numbers, not adjectives

Only the synthesis thread reads the answer key, and only after all findings are frozen.

- **Recall** — how many of the prior pass's findings did the blind pass re-find, over the
  uncontaminated denominator? Low recall means high variance and no single pass should be trusted.
- **Precision** — does the new pass contradict any prior finding? Contradictions are evidence that
  the prior "confirmed" was weaker than it read.
- **Net-new** — what the new pass found that the prior missed.
- **The prediction, checked** — including the wrong half.

Recall is the headline. It tells you how much to trust *any* single review, which outlives every
individual bug in the report.

## 7. Know when to stop

If a pass finds **more** than its predecessor against an equal-or-stricter standard, the loop has
hit its floor. Stop and disclose the residual. Do not start another cycle on momentum, and do not
quietly redefine the bar.

**A loop that hits its floor is a more useful artifact than a clean pass.** A clean pass means the
loop stopped finding things; a floor-hit documents exactly where the method's limit is. Ship the
disclosure.

---

## Caveat to state plainly in the writeup

This measures a review method using the same method. It reveals **variance, not ceiling**: a
defect neither pass can see is invisible to both, and low recall is evidence about the process, not
proof the code is worse than believed. Say so rather than letting the number imply more than it
supports.

## Checklist

- [ ] Exit bar + prediction + process-failure clause written before launch, frozen after
- [ ] Answer key moved out of the tree, or exclusions mandated in every launch prompt
- [ ] Auto-loaded files (`CLAUDE.md`, descriptor) audited for leaked findings; denominator adjusted
- [ ] "Declaring contamination is free" stated in every reviewer prompt
- [ ] Gates attacked with mirror images; gate list enumerated from source
- [ ] Verification refutes by default; nulls counted as UNVERIFIED
- [ ] Intensity diffed against the prior pass and shown not to drop
- [ ] Recall / precision / net-new reported as numbers, with the wrong half of the prediction
- [ ] Residual disclosed if the bar was not met, without redefining the bar
