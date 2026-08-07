---
paths:
  - "docs/decisions/**"
---

# ADR Writing Concepts

ADRs are dense with fact-claims and decisions that downstream PRs and future ADRs inherit. The concepts below are what to preserve when drafting.

For new ADRs (NNN-numbered files), prefer the `/claude-kit:write-adr` skill (from the `claude-kit@claude-kit` plugin, wired in `.claude/settings.json`) — it handles numbering, structure discovery, and the review loop. Pastura keeps no local copy: the kit skill derives the ADR format from this repo's own most recent ADRs rather than hardcoding one, so the house style tracks reality instead of drifting from it. The concepts below apply at draft time inside the skill AND when amending existing ADRs (the skill's scope is new-file creation only).

This file is the skill's `ADR_RULES_PATH` — it discovers `.claude/rules/adr*.md` and passes the path into both reviewer prompts, and what is written here takes precedence over anything the skill infers from a template ADR. Project facts the skill cannot re-derive therefore belong in § 4 below.

**§1 and §2 must stay in this file — do not relocate them behind a pointer the way §3 was.** Two independent reasons. (a) Eleven shipped citations across nine ADRs address them by section number or heading (`ADR-002`, `-004` ×2, `-011`, `-012`, `-016`, `-021`, `-023` ×2, `-027`, `-028`), so moving either breaks all of them at once. (b) `write-adr` forwards *this path* to its reviewers and deliberately declines to carry mechanism-contract criteria itself, on the grounds that they arrive through `ADR_RULES_PATH` — a channel its own SKILL.md notes fails with no error. A reviewer handed a pointer instead of §2 would silently stop applying it. §3 has neither property: nothing cites it and nothing routes it, which is why it could move.

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

**Read [`docs/decisions/adr-writing-guide.md`](../../docs/decisions/adr-writing-guide.md) before you finish drafting or amending an ADR.** Where §1 verifies each *individual* citation, this is the **cross-citation** pass: when the same fact appears in N places all N must agree, and any arithmetic derived from a citation must match the cited dates / SHAs. Critic and code-reviewer subagents check framing and rule-compliance, not mechanical cross-citation arithmetic — the writer is the only reliable check.

The guide carries the four-step grep checklist (dates / short SHAs / `file:line` / period words) and two recurring variants beyond plain arithmetic — projection-vs-measurement, and status-flip staleness on amendment. It lives outside this file because it is a once-per-draft mechanical pass, not something an ADR *reader* needs in context.

## 4. Numbering facts this repo carries

Kept deliberately short: `/claude-kit:write-adr` already handles sentinel ids,
reservation lookup, the conditional Options table, and the roadmap phase read.
Restating those here would duplicate kit-canonical text with no reconcile
header — the drift surface `subagent-usage.md` et al. exist to prevent. Only
what the skill cannot derive belongs here.

- **A new ADR must be hand-appended to two indexes**, neither of which the
  skill writes: `docs/decisions/INDEX.md` (full summary paragraph) and
  `CLAUDE.md` § "Reference Documents" → ADR roster (title only, kept
  **byte-identical** to the INDEX `## ADR-NNN — <title>` heading). Nothing at
  commit or merge time catches a skip. `consistency-audit`'s `adr_roster_drift`
  compares the roster, the INDEX headings and the **tracked** `ADR-*.md` files
  and files an issue — but only when someone runs it, and it does not demand
  listings for an ADR whose file is still untracked (third bullet).
- **`ADR-006` is reserved but unwritten** — Cloud API implementation details,
  recorded in `CLAUDE.md` § "Reference Documents" and `docs/decisions/INDEX.md`
  with no file on disk. It is a gap in the listing, not a free slot. Its
  `CLAUDE.md` entry must stay a **table row with the path in cell 1** —
  `consistency-audit`'s `load_reserved_adrs` parses that shape to suppress
  `dangling_adr` false positives, and fails open (empty set) if it changes.
  `unparsed_adr_reservation` announces that parse miss rather than leaving it
  silent — but only on the next audit run, so do not rely on being told.
- **Amending a large ADR: read its own placement rule first.** ADR-028 § "Where
  new amendment content goes" is the house pattern — values and standing
  invariants go in the **body** where the next reader looks; derivation,
  measurements and retracted drafts stay in the amendment, which is why
  amendments are not trimmed away later; superseding an earlier one marks it in
  place rather than rewriting it. Stated here because nothing enforces it: no
  lint, no gate, and `consistency-audit` has no amendment-**placement**
  detector, so it is reviewer-enforced and only fires if it is loaded. It
  generalises to any ADR past the size where a reader can hold its section
  structure (#1382).
- **What *is* enforced is findability, not placement.** `consistency-audit`'s
  `adr_navigation_missing` files an issue when a tracked ADR reaches 600 lines,
  is at least half amendment by section span, and has no `## How to read this
  ADR` section. It says nothing about whether a given value landed in the body
  or in an amendment — that judgment is still yours. Two ways to discharge it:
  add a navigation section whose heading starts `## How to read` (the ADR-028
  pattern, and the literal shape matched — `## Navigation` will not satisfy
  it), or, if you judge the ADR navigable as it stands, record
  `<!-- nav-exempt: <reason> -->` **on a line of its own, unindented** — it is
  matched at column 0, so a marker inside a list item, a block quote or an
  indented code block does not count. Closing the issue without one of those
  re-files it on the next run. The detector never proposes deleting or trimming
  an amendment, for the reason in the bullet above.
- **A file listing can also *over*-report.** The skill's reservation check
  covers a listing that under-reports; the inverse also happens here — an ADR
  draft sitting **untracked** in one checkout is visible to `ls` but absent for
  every other contributor and in CI. Confirm with `git ls-files` before treating
  a high-numbered file as evidence about the sequence, and check open PRs and
  concurrent sessions before claiming a number.
