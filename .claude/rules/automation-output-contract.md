---
paths:
  - ".claude/skills/**"
---

# Output Contract for unattended generators

> Derived from [claude-kit](https://github.com/tyabu12/claude-kit) `docs/automation-output-contract.md` —
> the generic core is canonical there; reconcile one-way (kit → Pastura). A consumer copy must never
> become the source.

A **generator** is any skill that runs unattended and produces artifacts a human must review — a docs-fix PR, an issue, a digest. The scarce resource it spends is the reviewer's attention. A generator joins the family by carrying the imperative "read this file before Step 0" pointer in its own body, not by being listed here; a skill whose only output is a gitignored local digest is not bound.

## The contract

0. **PRs are always Draft, and a generator never actuates.** `--draft` is the first flag of `gh pr create`; never mark a PR ready, merge, close an issue, or push to a default branch. Rule 3's exemption rests on this.
1. **Mechanically-determined fix → one batched Draft PR.** A finding is auto-fixable only when the correct value is *uniquely determined by an authoritative source* (a lockfile version, a build-setting deployment target). Batch every such fix from one run into a **single** Draft PR.
2. **Judgment-needed → issue only, never an auto-fix.** The issue body carries a **confidence score** and an explicit **counter-evidence** section, both produced back at detection, not composed at filing time (rule 6).
3. **The auto-fix path edits authoritative-source-computed values only — never free-form prose — and splices at the detected token's exact offset, not by free-text replace.** This bound is what makes omitting a code-review pass safe. **Precondition**: a detector that cannot report the exact offset does not qualify for the auto-fix path at all — "replace the first match" is the free-text replace this rule bans, however mechanical the value.
4. **Backpressure.** Each generator caps its own work-in-progress and the family carries an **aggregate ceiling**; both are project-owned. A generator's cap is canonical in its own skill, the ceiling in `.claude/skills/triage-guardian/SKILL.md` § "Backpressure — canonical definition (single source of truth)".
5. **Manual-first.** Detectors run dry-run by default; trust the output only after a human has eyeballed it for a given repo state. Never let a skill self-register its own schedule.
6. **Conservative *output*, exhaustive detection — filter at the output stage and account for the drops.** The precision bias stays (a wrong auto-fix PR, a false issue or a wrong "discard this" spends reviewer attention *and* erodes trust, while a miss only defers work), but must not move upstream into the detector.
   - **Detection is for coverage — do not filter here.** Enumerate every candidate; anything routing to rule 2 carries a **confidence**, an **estimated severity** and a **counter-evidence** line from the moment it is found. A detector nearing its coverage ceiling stops and says so rather than truncating quietly. Only three suppressions are legitimate here, each owing a count of what it removed: an enumerated **by-design roster** handed to the detector verbatim; an **evidence precondition** (no exact anchor, no concrete before → after ⇒ not a finding); a **quota**, meaning *rank-then-truncate over an already-enumerated list* — never a cap on generating candidates, which cannot name what it excluded. State any bar as a concrete predicate, never as a qualitative "important".
   - **The output stage filters, conservatively, and leaves a trail.** Vet, dedup and rank here; short of decisive evidence route to human judgment, not up to "ready" or down to "discard". Publish the arithmetic — **found / filtered / deduped / surfaced**, plus whatever was capped — into a channel the run already writes, and keep each rejection where the *next* run sees it. An uncounted drop is indistinguishable from a finding never made.

### Why an auto-fix PR may skip a code-review pass

Not because the diff is small: the PR is always **Draft**, so a human merge is the review gate, and rule 3 bounds the edit to a value with exactly one correct answer. **If rule 3 is relaxed, restore the reviewer pass.** A generator that writes arbitrary code (`queue-consumer`) never qualifies.

## Backpressure

The **aggregate** ceiling is advisory — the per-generator hard caps remain the real bound — so its read-then-act race (two generators both observe `n`, both proceed to `n+2`) is benign.

**A per-generator cap is not.** "At most one open Draft" assumes a single writer; two overlapping runs can each observe zero and both open one. Either serialize runs (never schedule a generator so it can overlap itself) or re-check after acting: push the branch, re-query for a sibling, and abandon without opening a PR if one won the race.

**The judgment lane is bounded by nothing here.** Both caps count open Draft PRs; rule 2's issues sit outside that accounting, and rule 6's exhaustive detection lands its increment precisely there. Cap issues per run as well — a cap on the *flow*, leaving the stock deliberately unbounded. The number is retuned per repo and canonical in the skill of the only generator filing issues unattended.

## `gh` read-surface traps (Draft-triage automation)

Version-dependent CLI behaviours; re-check on a `gh` upgrade.

- **`gh pr checks <N>` exits non-zero on pending (8) and failing (1)** — exactly the PRs a triage pass needs to classify, so a bare call aborts a `set -e` loop. The JSON form exits 0 across states:
  ```bash
  gh pr checks <N> --json bucket --jq '[.[].bucket] | group_by(.) | map({(.[0]): length}) | add'
  ```
  Read: all `pass`/`skipping` ⇒ green; any `fail`/`cancel` ⇒ red; any `pending` ⇒ still running.
- **A PR with zero checks yields `null`** from that `add` over an empty array. `null` is *unknown*, **not** green — never promote it to a ready/mergeable bucket.
- **`mergeable` or `mergeStateStatus` can be `UNKNOWN`.** GitHub computes merge state lazily, so an untouched Draft may return it; it is not an error. Treat **either** field as unknown and route to human judgment. Otherwise `DIRTY` = conflicts, `BEHIND` = behind base, `CLEAN`/`UNSTABLE` = mergeable (`UNSTABLE` = non-required checks failing or pending).
