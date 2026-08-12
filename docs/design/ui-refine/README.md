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
   proposal a run **considered**, not only the ones it surfaced: survivors with
   status `proposed`, adversarial-filter drops as `rejected`, and quota
   truncations as `parked`. Each run dedups against it and never re-proposes a
   tracked or rejected-with-reason item. This is what kills the daily-repetition
   flood that a diff gate would otherwise prevent. **`parked` is the one status
   that does not suppress** — a candidate the quota deferred was never judged, so
   it competes again next rotation rather than being silently buried.
2. **Rotating lens** — [`lenses.md`](lenses.md) defines seven critique lenses;
   each run uses exactly one, selected deterministically by weekday (`date +%u`).
   Forces depth over breadth and spaces proposals across the week.
3. **Quota + forced ranking** — at most 1–2 proposals reach the digest per run.
   The quota is applied **after** the filters, as a ranked truncation over a list
   that was enumerated first — never as a cap on generating candidates. That
   distinction is Output Contract rule 6 and it is not cosmetic: a cap applied
   while generating cannot name what it excluded, so the loss is invisible (two
   surfaced proposals look identical whether the pass found two or twenty). The
   digest still receives 1–2 items — what changed is that everything below the
   cut is now named and re-rankable.
4. **Design-system anchor** — every proposal must cite the
   [design-system](../design-system.md) principle (or a HIG / accessibility
   guideline) it advances, plus a concrete before → after. Vague "make it nicer"
   is rejected before it reaches the digest.
5. **Adversarial self-filter** — a second pass tries to *reject* each candidate
   (already by-design? subjective preference? out of scope per the ROADMAP?
   would a maintainer say "considered, no"?). The "already covered" test splits
   on what the UI *actually does*: a screen that **correctly follows** the
   convention is noise → drop; a screen that **violates** a spec-determined value
   is the highest-value finding → keep it as a **compliance gap** (a code-fix,
   surfaced separately from judgment-based *design proposals*). Only survivors
   reach the digest — but every drop reaches the **ledger**, with the failing
   test named, so a filter that is too tight becomes visible instead of just
   producing quiet runs.

This inherits the brush-up family's shared **Output Contract** (canonical text:
[`.claude/rules/automation-output-contract.md`](../../../.claude/rules/automation-output-contract.md)).
The binding rules for a digest-only generator are **rule 2**
(judgment output carries confidence + counter-evidence), **rule 5**
(manual-first: eyeball the output before trusting it), and **rule 6**
(conservative *output*, exhaustive detection — mechanisms 1, 3 and 5 above are
its three moving parts here).

## Ledger lifecycle (read before scheduling)

The ledger is **git-tracked** — it is the cross-run dedup memory, so it must
persist across runs and machines. But, exactly like every other family skill,
**the ui-refine skill never commits or pushes.** A run only *appends* rows to
the working-tree `ledger.md`; the change sits as an uncommitted working-tree
mutation. A **human commits the ledger append** — naturally bundled into the
same step that promotes a digest gem to an issue (see *Promotion*). This keeps
the skill's "files nothing, pushes nothing" posture intact (matching
scenario-refine's "a dirty working tree can never reach users" safety model).

**One narrow exception to append-only.** The skill may edit *in place* exactly
one thing: a `parked` row **it wrote itself**, when a later run re-derives the
same concept — refreshing its date, then either incrementing `N` in its
`[quota ×N]` prefix (parked again) or flipping it to `proposed` and dropping
that prefix (it cleared the quota). Without this a long-deferred candidate would
accrete one duplicate row per rotation, and the starvation guard that reads `N`
would never fire. Every other row, and every human-owned field, stays
the human's; the skill never edits a `proposed` / `filed` / `rejected` /
`deferred` / `done` row.

**Volume note.** Because drops are now recorded, the ledger grows faster than it
did when only survivors were written — that is the point (an unrecorded drop is
indistinguishable from a finding never made), but it is a git-tracked file a
human commits, so watch it across the first full rotation and prune or archive
if the file becomes unwieldy. No pruning policy is fixed yet; there is not
enough data to set one.

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
4. **A `parked` row needs no action.** It is a machine deferral — the quota cut
   it, nobody judged it — and the next run re-ranks it automatically, with a
   starvation guard that eventually forces it to the top. Promote it early by
   setting it to `filed (#N)` if you want it acted on now, or to `rejected` with
   a reason to take it out of the rotation for good. Leaving it alone is the
   correct default; do **not** set it to `deferred` unless you mean the human
   "considered, not now", which does suppress it.
5. **A machine-written `rejected` row is final — and you are the only way back.**
   Unlike `parked`, it *was* judged: the adversarial filter applied a named test
   and the row records which one (`[filter-drop: <test>]`). Suppressing it
   permanently is what the Output Contract asks for (a rejection kept where the
   next run can see it), so the skill will never revisit it on its own.
   **The caveat is that those tests read the current state** — "already
   by-design?" and "already covered?" are answered against the design system as
   it stands. So when a design-system convention changes, grep `ledger.md` for
   `[filter-drop:]` rows citing the test that relied on it and un-reject the ones
   whose basis moved (set them back to `proposed`, or delete the row). Nothing
   automates this; the prefix exists so the sweep is a grep rather than a reread.
6. Commit the `ledger.md` change (and only that) alongside whatever issue/PR work
   the promotion triggered.

## Known coverage limitations

The empty / error gap is now **closed** (#811). The capture step
(`scripts/ui-tour.sh`) seeds the genuinely empty (zero scenarios / zero results /
no-search-match) and the gallery offline / load-failure surfaces via
`--ui-test-seed-empty-inventory` / `--ui-test-seed-empty-gallery` /
`--ui-test-seed-gallery-offline`. Screens 10–14 in
[`../screenshots/README.md`](../screenshots/README.md) render them, so the **L5**
(empty / error / edge) and **L6** (copy — the on-screen text *is* the UITest
fixture) lenses now have real empty/error copy to critique. One caveat: the
gallery `.error` LoadState ("Error" + Retry) is **not** captured — it is
unreachable dead code in `SharedScenariosViewModel` (never assigned), so the
reachable `.empty` ("Gallery Unavailable") stands in for the offline /
load-failure surface.

The motion path still inherits a parallel gap — § 5.5 DL-Progress-Dots (motion
timing in § 6) and the bubble-entrance animation are unreachable under
`--ui-test` (`../motion/README.md` § Deferred). Those live-simulation surfaces
need a canned-response queue for `MockLLMService`, a distinct blocker that
unblocks **L4** (DL-dot / interactive-state anchors), not L5/L6. Until it lands,
still treat L4's DL-dot / interactive-state anchors as coverage-bounded.

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
| `ledger.md` | ✅ | Proposal dedup + rejection memory (skill appends — and may update its own `parked` rows in place; human commits) |
| `digests/README.md` | ✅ | Explains the digests directory |
| `digests/*.md` | ❌ gitignored | Per-run digest artifacts |
