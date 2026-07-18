---
paths:
  - "docs/decisions/**"
---

# ADR Writing Concepts

ADRs are dense with fact-claims and decisions that downstream PRs and future ADRs inherit. The concepts below are what to preserve when drafting.

For new ADRs (NNN-numbered files), prefer the `/claude-kit:write-adr` skill (from the `claude-kit@claude-kit` plugin, wired in `.claude/settings.json`) — it handles numbering, structure discovery, and the review loop. Pastura keeps no local copy: the kit skill derives the ADR format from this repo's own most recent ADRs rather than hardcoding one, so the house style tracks reality instead of drifting from it. The concepts below apply at draft time inside the skill AND when amending existing ADRs (the skill's scope is new-file creation only).

This file is the skill's `ADR_RULES_PATH` — it discovers `.claude/rules/adr*.md` and passes the path into both reviewer prompts, and what is written here takes precedence over anything the skill infers from a template ADR. Project facts the skill cannot re-derive therefore belong in § 4 below.

## 1. Verify fact-claims at write time, not at review time

ADR / spec / decision-record bodies have **higher fact-claim density** than ordinary prose. Citations (`file:line`, `.claude/rules/` section names, Swift / Apple SDK behavior) are *load-bearing for the decision*. A wrong citation propagates: the next implementer copy-pastes from the ADR, and subsequent ADRs build on a false premise.

Before committing a fact-claim line:

- Citing `file:line`? — Read the line.
- Citing a `.claude/rules/*.md` or `CLAUDE.md` section? — Read the section.
- Asserting Swift / language / SDK behavior? — confirm via existing-code grep hit or an authoritative source. Memory-based "Swift can do X" is not enough for ADR text.
- Bringing in a citation that wasn't in the source plan (new rule / pattern / spec)? — Read it.

The 5–10 minute investment per commit prevents the kind of 3-review-round cycle that landed 4 fact-errors in ADR-010 body (see #370).

Pairs with `knowledge-layering.md` § "Rule-writing self-check" — different surface, same shape: execute every load-bearing assertion before commit.

## 2. Mechanism contract over pinned model thresholds

When drafting a DoD criterion that reads `≥ N% on model X`, default to a **mechanism contract** framing instead of pinning the threshold.

- **Pinned threshold** — clear gate, but binds the ADR to one backend; every future model adoption (LiteRT-LM, new quantization, Qwen / Gemma swap) requires ADR amendment + re-measurement against the threshold.
- **Mechanism contract** — define the detector + retry + event + harness. The ADR survives model swaps. Per-model adherence becomes a run-time judgement read off harness output, not an ADR-amendment question.

Pastura's roadmap includes multi-model and LiteRT-LM migration, so default toward mechanism contracts. Pin only when the criterion is **single-model-by-design** (e.g., "this ships for Gemma E2B only").

If a plan surfaces a quantitative gate, surface the trade-off to the user at plan time rather than silently committing one framing. See #405 (ADR-010 D5) for the case that collapsed an `if M ≥ 80% pin else fork to PR3` contingency by pivoting to mechanism contract.

## 3. Inter-citation consistency — dates, SHAs, arithmetic

Distinct from §1 (verify each *individual* citation). This is **cross-citation**:
when the same fact appears in N places, all N must agree, and any arithmetic
*derived* from a citation must match the cited dates / SHAs. Critic and
code-reviewer subagents evaluate framing and rule-compliance, not mechanical
cross-citation arithmetic — so the writer is the only reliable check.

After drafting an ADR / spec / decision record:

1. **Grep every date** (`YYYY-MM-DD`). Sort mentally; cross-check each span
   claim ("predates by N months", "over a year", "X older than Y") against the
   actual gap. (An ADR once shipped "predates by over a year" while its own
   cited commit dates were ~32 days apart — passed two critic rounds + one
   code-reviewer; caught by a third-party cross-reference.)
2. **Grep every short SHA.** Each must resolve in `git log` and its subject
   match the cited claim.
3. **Grep every `file:line`.** Read each; confirm the cited content is there.
4. **Grep period words** (`year` / `month` / `week` / `day`) and recompute the
   span from the dates you cited.

Two recurring variants beyond plain arithmetic:

- **Projection vs measurement.** When a metric appears across a *series* of
  checkpoints (weekly spikes, CI readings, perf runs), cite the **latest
  measured** value — not a superseded earlier **projection**. The rosy early
  estimate is the trap: an evidence-synthesis ADR written from memory reaches
  for it. (ADR-004 §9.3 once cited a week-1 CI *projection* with ~14 min
  headroom as the cold-pipeline evidence; the later week-3 *measurement* was
  17m40s with ~2m20s headroom and a flagged ceiling breach.)
- **Status-flip staleness.** When amending an ADR to record that a condition
  flipped (a migration trigger fired, a dependency became available, something
  got deprecated), the original present-tense rationale ("X is unavailable",
  "no SDK", status tables) now contradicts the new section. Grep every
  present-tense claim about the flipped condition and reframe to **dated
  past-tense + a forward pointer** — do not delete (it's the original decision
  rationale). A section's date header doesn't cover present-tense bullets/rows
  below it (a reader landing mid-section misses it). The **cherry-port variant**
  is worse: porting docs authored *before* a later decision spreads stale
  framing far beyond the renamed heading, and one decision can fork a single
  term into two axes needing separate replacement vocab — full-doc grep the old
  plan's vocabulary, not just the section you renamed.

## 4. Numbering facts this repo carries

Kept deliberately short: `/claude-kit:write-adr` already handles sentinel ids,
reservation lookup, the conditional Options table, and the roadmap phase read.
Restating those here would duplicate kit-canonical text with no reconcile
header — the drift surface `subagent-usage.md` et al. exist to prevent. Only
what the skill cannot derive belongs here.

- **`ADR-006` is reserved but unwritten** — Cloud API implementation details,
  recorded in `CLAUDE.md` § "Reference Documents" and `docs/decisions/INDEX.md`
  with no file on disk. It is a gap in the listing, not a free slot.
- **A file listing can also *over*-report.** The skill's reservation check
  covers a listing that under-reports; the inverse also happens here — an ADR
  draft sitting **untracked** in one checkout is visible to `ls` but absent for
  every other contributor and in CI. Confirm with `git ls-files` before treating
  a high-numbered file as evidence about the sequence, and check open PRs and
  concurrent sessions before claiming a number.
