# ui-refine — UI improvement-proposal generator

`ui-refine` is a **manual-first** brush-up generator that periodically looks at
the *current* app UI and proposes concrete improvements. It is the design-layer
sibling of [`scenario-refine`](../../../.claude/skills/scenario-refine/SKILL.md):
where scenario-refine evaluates and polishes the existing *scenario* inventory,
ui-refine evaluates and polishes the existing *UI*.

The skill that drives one cycle lives at
[`.claude/skills/ui-refine/SKILL.md`](../../../.claude/skills/ui-refine/SKILL.md).

## What it is — and is NOT

- **It is improvement-proposal generation, NOT regression detection.** It does
  **not** diff today's screenshots against a baseline. The whole point is to
  surface *latent* improvements — things that have been unchanged for months but
  on fresh reflection should be reconsidered. A diff gate cannot find those.
- **It is digest-only.** A run writes a ranked, dated **digest** of survivor
  proposals. It files **no** issues and registers **no** schedule. Promoting a
  digest item to an issue is a deliberate human step (see *Promotion* below).

## Why the anti-flood machinery exists

An LLM asked to "propose UI improvements" against a static, unchanged UI floods,
because it (a) re-derives the same top-of-mind ideas every run and (b) emits a
high volume of low-value / subjective findings. Five mechanisms keep a periodic
open-ended critique pass from drowning the human's review attention — the scarce
resource the whole brush-up family is built to protect:

1. **Proposal ledger** (the linchpin) — [`ledger.md`](ledger.md) records every
   proposal ever surfaced, with status. Each run dedups against it and never
   re-proposes a tracked or rejected-with-reason item. This is what kills the
   daily-repetition flood that a diff gate would otherwise prevent.
2. **Rotating lens** — [`lenses.md`](lenses.md) defines seven critique lenses;
   each run uses exactly one, selected deterministically by weekday (`date +%u`).
   Forces depth over breadth and spaces proposals across the week.
3. **Quota + forced ranking** — at most 1–2 proposals per run. "If you could
   change one thing under today's lens, what and why."
4. **Design-system anchor** — every proposal must cite the
   [design-system](../design-system.md) principle (or a HIG / accessibility
   guideline) it advances, plus a concrete before → after. Vague "make it nicer"
   is rejected before it reaches the digest.
5. **Adversarial self-filter** — a second pass tries to *reject* each candidate
   (already by-design? design-system already covers it? subjective preference?
   out of scope per the ROADMAP? would a maintainer say "considered, no"?). Only
   survivors reach the digest.

This inherits the brush-up family's shared **Output Contract** (canonical text:
[`.claude/skills/consistency-audit/SKILL.md`](../../../.claude/skills/consistency-audit/SKILL.md)
§ "Output Contract"). The binding rules for a digest-only generator are **rule 2**
(judgment output carries confidence + counter-evidence) and **rule 5**
(manual-first: eyeball the output before trusting it).

## Ledger lifecycle (read before scheduling)

The ledger is **git-tracked** — it is the cross-run dedup memory, so it must
persist across runs and machines. But, exactly like every other family skill,
**the ui-refine skill never commits or pushes.** A run only *appends* rows to
the working-tree `ledger.md`; the change sits as an uncommitted working-tree
mutation. A **human commits the ledger append** — naturally bundled into the
same step that promotes a digest gem to an issue (see *Promotion*). This keeps
the skill's "files nothing, pushes nothing" posture intact (matching
scenario-refine's "a dirty working tree can never reach users" safety model).

**Persistence constraint for the deferred scheduling phase:** because the ledger
must persist to do its job, ui-refine must run in the **persistent main
checkout, never a throwaway `/orchestrate` worktree** — a worktree-local ledger
would lose its dedup memory the moment the worktree is removed, silently
defeating mechanism 1. This is the same carve-out scenario-refine makes for its
journal. Pin this constraint before any Routine is wired up.

## Promotion (digest → issue, by hand)

1. Read the latest digest under [`digests/`](digests/).
2. For a proposal worth acting on, open an agent-ready issue by hand (apply the
   project's issue conventions), and update that proposal's row in `ledger.md` to
   `filed (#N)`.
3. For a proposal you decide against, set its row to `rejected` with a one-line
   reason — this is what stops it from resurfacing next rotation.
4. Commit the `ledger.md` change (and only that) alongside whatever issue/PR work
   the promotion triggered.

## Deferred next phases (NOT in this prototype)

This prototype stops at "run by hand → produce a digest → human triages." Later,
in order:

1. **Manual precision runs** — run by hand across a full lens rotation; eyeball
   the digests for precision (false-positive rate, repetition). This is the
   manual-first checkpoint (Output Contract rule 5) before any automation.
2. **Routine scheduling** — register a local Routine (NOT a cloud routine: the
   capture step is local-only). It must run in the **persistent main checkout**
   (see the persistence constraint above). The capture inherits
   `scripts/ui-tour.sh`'s preconditions — a UDID-pinned simulator, `jq`, multi-
   minute build, and the concurrent-session simulator gate
   (`.claude/rules/xcodebuild-cli.md`) — so it cannot run on cloud infra, same as
   scenario-refine's local-only carve-out.
3. **Opt-in auto-filing** — only after precision is proven, optionally let the
   skill file issues directly. At that point the family **WIP ceiling**
   (`AUTOMATION_WIP_CEILING`, canonical in
   [`.claude/skills/triage-guardian/SKILL.md`](../../../.claude/skills/triage-guardian/SKILL.md)
   § Backpressure) becomes load-bearing and must gate the run. It is **inert**
   for the current digest-only phase because ui-refine opens no branch / PR, so
   the `^(audit|agent)/` predicate never matches it.

## Layout

| Path | Tracked? | What |
|------|----------|------|
| `README.md` | ✅ | This file |
| `lenses.md` | ✅ | The 7 rotating critique lenses + weekday mapping |
| `ledger.md` | ✅ | Proposal dedup memory (skill appends, human commits) |
| `digests/README.md` | ✅ | Explains the digests directory |
| `digests/*.md` | ❌ gitignored | Per-run digest artifacts |
