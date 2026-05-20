---
paths:
  - "docs/decisions/**"
---

# ADR Writing Concepts

ADRs are dense with fact-claims and decisions that downstream PRs and future ADRs inherit. Two concepts to preserve when drafting.

For new ADRs (NNN-numbered files), prefer the `/write-adr` skill (`.claude/skills/write-adr/SKILL.md`) — it handles auto-numbering, structure scaffold, and the review loop. The two concepts below apply at draft time inside the skill AND when amending existing ADRs (the skill's scope is new-file creation only).

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
