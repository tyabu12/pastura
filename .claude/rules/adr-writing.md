---
paths:
  - "docs/decisions/**"
---

# ADR Writing Concepts

ADRs are dense with fact-claims that downstream PRs and future ADRs inherit. For new ADRs prefer the `/claude-kit:write-adr` skill (`claude-kit@claude-kit`); the concepts below apply inside it and when amending an ADR, which is outside its scope.

This file is that skill's `ADR_RULES_PATH`: it reaches both reviewer prompts, and takes precedence over anything the skill infers from a template ADR. §1 and §2 are cited by section number from nine ADRs and are the payload those reviewers receive — do not renumber them, and do not move either behind a pointer.

## 1. Verify fact-claims at write time, not at review time

Citations (`file:line`, `.claude/rules/` section names, Swift / SDK behavior) are load-bearing, and a wrong one propagates — the next implementer copy-pastes it and the next ADR builds on it. Before committing one:

- Citing `file:line`? — read the line. Citing a `.claude/rules/*.md` or `CLAUDE.md` section? — read the section. Bringing in a citation that wasn't in the source plan? — read it.
- Asserting Swift / language / SDK behavior? — confirm via an existing-code grep hit or an authoritative source. Memory-based "Swift can do X" is not enough for ADR text.

## 2. Mechanism contract over pinned model thresholds

When drafting a DoD criterion that reads `≥ N% on model X`, default to a **mechanism contract** instead of pinning the threshold. A **pinned threshold** is a clear gate but binds the ADR to one backend: every model adoption (LiteRT-LM, a new quantization, a Gemma swap) then needs an amendment plus re-measurement. A **mechanism contract** defines the detector + retry + event + harness instead — the ADR survives model swaps, and per-model adherence becomes a run-time judgement read off harness output.

Pastura's roadmap includes multi-model and LiteRT-LM migration, so default toward mechanism contracts. Pin only when the criterion is **single-model-by-design** ("this ships for Gemma E2B only"), and put the trade-off to the user rather than silently committing one framing.

## 3. Inter-citation consistency — dates, SHAs, arithmetic

**Read [`docs/decisions/adr-writing-guide.md`](../../docs/decisions/adr-writing-guide.md) before finishing a draft or an amendment.** Where §1 verifies each citation individually, the guide carries the cross-citation pass: N copies of one fact must agree, and derived arithmetic must match the cited dates and SHAs.

## 4. Index and numbering facts this repo carries

Only what `/claude-kit:write-adr` cannot derive belongs here.

- **A new ADR must be hand-appended to two indexes** the skill does not write: `docs/decisions/INDEX.md` and the `CLAUDE.md` ADR roster (title only, **byte-identical** to the INDEX `## ADR-NNN — <title>` heading). Nothing at commit or merge time catches a skip.
- **Do not mirror a mutable inventory count into an INDEX entry** — tokens paired, sites swept. A count-keyed sweep cannot find such a mirror: grepping the current number matches every *up-to-date* copy and misses exactly the stale ones. **The test: can the number change without the decision changing?** If yes it is an inventory; a cardinality *of the design* ("two Models enums") is not. A *relative* claim ("the quietest of the five") goes stale the same way.
- **`ADR-006` is reserved but unwritten**, so its `CLAUDE.md` entry must stay a **table row with the path in cell 1**: `consistency-audit`'s `load_reserved_adrs` parses that shape to suppress `dangling_adr` false positives and fails open if it changes.
- **Amending a large ADR: read its own placement rule first.** ADR-028 § "Where new amendment content goes" is the house pattern: values and standing invariants in the **body** where the next reader looks, derivation and retracted drafts in the amendment — which is why amendments are not trimmed away later. Nothing enforces it.
- **Findability is enforced; placement is not.** `consistency-audit`'s `adr_navigation_missing` fires on a tracked ADR past 600 lines that is at least half amendment and has no navigation section. Both discharge routes are literal-matched: a heading starting `## How to read` (`## Navigation` fails), or `<!-- nav-exempt: <reason> -->` **on its own line at column 0** — indented or inside a list item or code block it does not count.
- **A file listing can also *over*-report.** An **untracked** ADR draft is visible to `ls` but absent for every other checkout and for CI. Confirm with `git ls-files` before treating a high-numbered file as evidence about the sequence.

