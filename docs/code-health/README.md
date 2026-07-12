# code-health-audit — latent code-health improvement generator

> **⚠️ PROTOTYPE.** This skill is **not scheduled**, **manual-first**, and
> **digest-only**. It never edits source, files issues, opens PRs, or commits.
> A run produces a ranked digest a human triages by hand. Auto-filing and
> scheduling are deferred (see *Deferred next phases*).

`code-health-audit` is a **manual-first** brush-up generator that periodically
sweeps a code layer (Engine/LLM to start) and surfaces **latent** improvements —
correctness/logic-consistency risks and meaningful test-coverage gaps — that a
diff-scoped gate structurally cannot see. It is the code-layer sibling of
[`ui-refine`](../../.claude/skills/ui-refine/SKILL.md) (UI) and
[`scenario-refine`](../../.claude/skills/scenario-refine/SKILL.md) (scenarios):
where those polish the existing UI / scenario inventory, this one polishes the
existing **code**.

The skill that drives one cycle lives at
[`.claude/skills/code-health-audit/SKILL.md`](../../.claude/skills/code-health-audit/SKILL.md).

## What it is — and is NOT

- **It is latent-improvement generation, NOT a diff review.** It does **not**
  review a branch diff. `/code-review` (working-tree diff) and the
  `code-reviewer` subagent (feature-branch diff) already cover *changed* lines.
  This sweep finds defects in code no PR is touching — e.g. two long-standing
  code paths that silently disagree, which no diff gate ever puts side by side.
- **It is digest-only.** A run writes a ranked, dated **digest** of Vet-survived
  findings. It files **no** issues and registers **no** schedule. Promoting a
  digest item to an agent-ready issue is a deliberate human step (see *Promotion*).

## Provenance — the pilot that motivated this

This skill's design is not speculative; it was derived from a live pilot run
(2026-07-12). Two Sonnet `Explore` finders swept Engine/LLM (one for
concurrency/isolation, one for test-coverage gaps), then the orchestrating Opus
session **Vetted** every finding by opening the cited code itself:

- **Test-coverage finder** — 4 findings, **all 4 survived Vet** (0 false
  positives). Two were latent correctness bugs, now filed as
  [#1056](https://github.com/tyabu12/pastura/issues/1056) (vote-tie winner
  diverges between `EliminateHandler` and `vote_winner`) and
  [#1057](https://github.com/tyabu12/pastura/issues/1057) (`WordwolfJudgeLogic`
  non-deterministic tie). Neither is reachable by a diff-scoped gate.
- **Concurrency finder** — **0 findings** for ~159k tokens: it compiler-verified
  ~12 by-design sites and self-rejected a plausible false positive.

Two lessons are baked into the skill as load-bearing mechanisms: **(1)** inject
the layer's by-design facts (the `.claude/rules/swift-isolation.md` conventions,
an explicit "these are deliberate — do not flag" list, relevant ADR decisions)
into every finder prompt — this is what kept the false-positive rate near zero;
**(2)** a **mandatory Vet** by the orchestrating model, opening every cited
location itself, is the second filter. The uneven yield (test-coverage 4/4 vs
concurrency 0) is why categories are **weighted**, not swept uniformly — but the
weights are an **n=1 prior**, to be re-tuned across the manual-first runs.

## The anti-flood machinery

An LLM asked to "find code-health improvements" over a large, well-tended
codebase floods, because it (a) re-derives the same findings every run and (b)
emits by-design behavior as if it were a defect. These mechanisms keep a periodic
open-ended sweep from drowning the human's review attention — the scarce resource
the whole brush-up family is built to protect:

1. **Proposal ledger** (the linchpin) — [`ledger.md`](ledger.md) records every
   finding ever surfaced, with **status** (`proposed` / `filed` / `rejected` /
   `done`) and a **stable concept fingerprint**. Each run dedups against it by
   **concept, not `file:line`** (code drifts, so a line-exact match would let an
   already-filed finding — e.g. #1056 — resurface at a new offset). This kills the
   re-derivation flood a diff gate would otherwise prevent, and stops re-filing
   what is already an open issue.
2. **By-design context injection** — every finder prompt carries the audited
   layer's deliberate patterns verbatim ("these are by-design, do not flag"), so
   the finder rejects them before they ever reach Vet. The pilot's concurrency
   finder cleared ~12 such sites this way.
3. **Category weighting + per-category cost ceiling** — finders are prioritized by
   observed yield (test-coverage / correctness high; concurrency down-weighted),
   and each finder carries a token ceiling so a low-yield category can't burn the
   run (the pilot's 159k-for-zero is the cautionary tale). Weights are a
   provisional n=1 prior — re-tune across runs.
4. **Mandatory Vet** — the orchestrating model opens every cited location itself
   and rejects by-design behavior, mis-attributed evidence, and duplicates.
   Digest excerpts come from the orchestrator's own reads, never a finder's
   report (a finder's line numbers are leads, not facts).

This inherits the brush-up family's shared **Output Contract** (canonical text:
[`.claude/skills/consistency-audit/SKILL.md`](../../.claude/skills/consistency-audit/SKILL.md)
§ "Output Contract"). The binding rules for a digest-only generator are **rule 2**
(judgment output carries confidence + counter-evidence) and **rule 5**
(manual-first: eyeball the output before trusting it).

## Ledger lifecycle (read before scheduling)

The ledger is **git-tracked** — it is the cross-run dedup memory, so it must
persist across runs and machines. But, exactly like every other family skill,
**the code-health-audit skill never commits or pushes.** A run only *appends*
rows to the working-tree `ledger.md`; the change sits as an uncommitted
working-tree mutation. A **human commits the ledger append** — naturally bundled
into the same step that promotes a digest finding to an issue (see *Promotion*).
This keeps the skill's "files nothing, pushes nothing" posture intact.

**Persistence constraint for the deferred scheduling phase:** because the ledger
must persist to do its job, this skill must run in the **persistent main
checkout, never a throwaway `/orchestrate` worktree** — a worktree-local ledger
would lose its dedup memory the moment the worktree is removed, silently
defeating mechanism 1 (same carve-out ui-refine / scenario-refine make). Pin this
before any Routine is wired up.

## Promotion (digest → issue, by hand)

1. Read the latest digest under [`digests/`](digests/).
2. For a finding worth acting on, open an **agent-ready** issue by hand (apply the
   project's issue conventions — self-contained spec, acceptance criteria, STOP
   conditions), and update that finding's row in `ledger.md` to `filed (#N)`.
3. For a finding you decide against, set its row to `rejected` with a one-line
   reason — this is what stops it resurfacing next run (e.g. the pilot's
   concurrency non-findings belong here so the category isn't re-swept blind).
4. Commit the `ledger.md` change (and only that) alongside whatever issue work the
   promotion triggered.

## Deferred next phases (NOT in this prototype)

This prototype stops at "run by hand → produce a digest → human triages." Later,
in order — and each gated behind the one before it:

1. **Manual precision runs** — run by hand across several category rotations;
   eyeball the digests for precision (false-positive rate, repetition). This is
   the manual-first checkpoint (Output Contract rule 5) before any automation, and
   the point at which the n=1 category weights get re-tuned.
2. **Routine scheduling** — register a local Routine that runs in the persistent
   main checkout (see the persistence constraint above).
3. **Opt-in auto-filing** — only after precision is proven, optionally let the
   skill file issues directly. At that point the family **WIP ceiling**
   (`AUTOMATION_WIP_CEILING`, canonical in
   [`.claude/skills/triage-guardian/SKILL.md`](../../.claude/skills/triage-guardian/SKILL.md)
   § Backpressure) becomes load-bearing and must gate the run. It is **inert** for
   the current digest-only phase because this skill opens no branch / PR, so the
   `^(audit|agent)/` predicate never matches it.

## Layout

| Path | Tracked? | What |
|------|----------|------|
| `README.md` | ✅ | This file |
| `ledger.md` | ✅ | Finding dedup memory — all statuses + concept fingerprint (skill appends, human commits) |
| `digests/README.md` | ✅ | Explains the digests directory |
| `digests/*.md` | ❌ gitignored | Per-run digest artifacts (ephemeral local logs) |
