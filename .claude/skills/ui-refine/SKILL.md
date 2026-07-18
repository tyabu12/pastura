---
name: ui-refine
description: Run one ui-refine cycle — capture the current app UI via ui-tour, critique it through today's rotating lens, adversarially filter the proposals against the proposal ledger and the design system, and write a ranked digest (files no issues, schedules nothing). Use when the user asks to run ui-refine, propose UI improvements, critique the current UI design, polish the UI, or run the UI design-refine pass.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# /ui-refine

One UI design-critique cycle: **capture → pick lens → propose → adversarial
filter → dedup → digest**. The design-layer sibling of `/scenario-refine`: where
refine evaluates and polishes the existing *scenario* inventory, ui-refine
evaluates and polishes the existing *UI*. Run from the repository root of the
**persistent main checkout** (see Safety boundary). Concept + data model:
[`docs/design/ui-refine/README.md`](../../../docs/design/ui-refine/README.md).

This is a member of the "brush-up automation" family (siblings: `consistency-audit`,
`triage-guardian`, `scenario-refine`, `code-health-audit`). It proposes UI **improvements** against the
*current* UI — it is **not** regression detection and does **not** diff against a
baseline. The whole point is to surface latent improvements a diff gate can't see,
while five anti-flood mechanisms keep an open-ended critique pass from drowning the
human's review attention (the scarce resource the family protects).

Optional args:

- `lens: L<n>` — run a specific lens (`L1`…`L7`) instead of today's weekday lens.
- `screen: <name>` — restrict the critique to one tour screen (e.g. `01-home`).

## Safety boundary (read first)

- **Writes ONLY under `docs/design/ui-refine/`** — a new digest file under
  `digests/` and appended rows on `ledger.md`. Any write elsewhere is a skill
  bug: abort and report.
- **Makes no `git` commit / push and no `gh` call.** A run leaves the ledger
  append as an uncommitted working-tree change; a **human** commits it during
  digest promotion (README § Ledger lifecycle). This matches scenario-refine's
  "a dirty working tree can never reach users" model.
- **Runs in the persistent main checkout, never a throwaway worktree.** The
  ledger is the cross-run dedup memory; a worktree-local ledger loses it on
  removal, silently defeating the linchpin mechanism.

## Non-goals

- **Files no issues, registers no schedule.** Output is a digest only. Promoting
  a digest item to an issue is a deliberate human step. Issue-filing and Routine
  scheduling are OUT of scope for this prototype (the manual-first precision
  checkpoint must clear first — README § Deferred next phases).
- **No regression / diff detection.** No baseline comparison; latent-improvement
  proposals are the product.
- **No code edits.** ui-refine never touches `Pastura/` source — it reads the
  rendered UI (screenshots) and proposes; humans implement.

## Output Contract (inherited from the brush-up family)

**Canonical text: `.claude/rules/automation-output-contract.md` — read it in
full before Step 0.** It is path-scoped to `.claude/skills/**`, which fires on a
skill *edit*, not on this skill's *execution*; nothing auto-loads it during a
run. The two rules that bind a digest-only generator:

- **Rule 2 — judgment output carries confidence + counter-evidence.** Every
  proposal in the digest carries a confidence and an explicit "why this might be
  wrong / why a maintainer might reject it" line. (Open-ended UI critique is pure
  judgment output, so this binds every entry.)
- **Rule 5 — manual-first.** Trust the digest only after a human has eyeballed
  the output across a full lens rotation at least once.

The family **WIP ceiling** (`AUTOMATION_WIP_CEILING`, canonical in
`.claude/skills/triage-guardian/SKILL.md` § Backpressure) is **inert** for this
digest-only phase: ui-refine opens no branch / PR, so the `^(audit|agent)/`
predicate never matches it and nothing of ui-refine's counts toward the ceiling.
It becomes load-bearing only at the deferred opt-in auto-filing phase. This skill
does **not** inline the ceiling literal — referencing the concept does not add a
file to triage-guardian's "keep in sync" set.

## Step 0 — Preflight (abort, don't degrade)

1. `command -v jq` — required by `scripts/ui-tour.sh`. Abort with a clear message
   if missing (`brew install jq`).
2. Confirm the working directory is the repository root (`scripts/ui-tour.sh` and
   `docs/design/ui-refine/` both exist).
3. Confirm `docs/design/design-system.md` and `docs/design/ui-refine/ledger.md`
   exist (the anchor source and the dedup memory).
4. Resolve the lens id early (the `lens:` arg, else `date +%u`) — Step 1's
   capture path branches on it. If it resolves to **L4**, also require `ffmpeg`
   (`brew install ffmpeg`): L4 captures motion via `scripts/motion-capture.sh`
   instead of `ui-tour.sh` (Step 1). Full anchor resolution still happens in
   Step 2; this is only the id needed to pick the capture path.
5. **Read `.claude/rules/automation-output-contract.md` in full.** It does not
   auto-load during a run (its `paths:` glob fires on a skill edit), so this is
   the only step that puts the contract in context.

If any check fails, **abort the cycle** — do not proceed against a partial setup.

## Step 1 — Capture the current UI (lens-aware)

The capture path branches on the lens id resolved in Step 0. **On any capture
failure or timeout, ABORT the cycle** (both paths) — never critique against
stale or missing artifacts; an empty / stale set produces hallucinated, flood-y
proposals, defeating the anti-flood goal. Report the failure and stop.

### Default lenses (L1–L3, L5–L7) — static screenshots

Run the tour to refresh the screenshots:

```sh
scripts/ui-tour.sh
```

This runs `ScreenshotTourTests` on the UDID-pinned simulator and writes the 8
fixture-driven PNGs to `docs/design/screenshots/` (takes several minutes incl.
the build; subject to the concurrent-session simulator gate per
`.claude/rules/xcodebuild-cli.md`). After it succeeds, confirm the expected PNGs
are present and freshly written (`docs/design/screenshots/*.png`). The covered
screens are listed in `docs/design/screenshots/README.md`.

### L4 (Motion & feedback) — motion filmstrips

Motion is a *time axis* a single screenshot can't show, so L4 captures
filmstrips **instead of** static PNGs. Run `motion-capture.sh` (never alongside
`ui-tour.sh` — see the concurrency invariant):

```sh
scripts/motion-capture.sh all   # launch variants: cold / warm / reduce-motion
```

This writes per-frame images + a tiled filmstrip under
`docs/design/motion/<variant>/` (requires `ffmpeg`; takes a few minutes incl.
the build). `all` covers the launch-animation surfaces (§ 6 transitions). The
`demo` typing variant (`scripts/motion-capture.sh demo`, DL-time demo replay) is
available when explicitly reviewing that surface, but is **not** part of the
default L4 capture. The `screen:` arg has **no effect under L4** — motion
artifacts are variant-indexed (`cold` / `warm` / `reduce-motion` / `demo`), not
tour-screen-indexed; variant selection beyond the `all` default is out of scope.
After it succeeds, confirm fresh frames are present under
`docs/design/motion/<variant>/frames/`.

**Concurrency invariant — never run `motion-capture.sh` and `ui-tour.sh` (or
`xcodebuild test`) against the same simulator at once.** motion-capture mutates
the sim's Reduce Motion setting and holds a video recorder, and the
`sim-dest.sh` gate only sees `xcodebuild test`, not `simctl io`
(`docs/design/motion/README.md` § "Don't run concurrently"). The L4 branch runs
motion-capture **exclusively** — it does not also run ui-tour.

**Coverage bound:** L4's § 5.5 DL-Progress-Dots and § 2.7 Interactive-States
anchors are currently **uncapturable** — `--ui-test` bypasses the download flow
and there is no interaction driver (`docs/design/motion/README.md` § Deferred).
Until launch-arg seeding lands (README § "Known coverage limitations"), L4's
motion critique is bounded to the launch (and explicit `demo`-typing) surfaces;
do not hallucinate DL-dot / pressed-state findings from frames that don't show
them.

## Step 2 — Pick today's lens

```sh
LENS=$(date +%u)   # 1=Mon … 7=Sun → lens L1…L7
```

Resolve `LENS` to its definition in
[`docs/design/ui-refine/lenses.md`](../../../docs/design/ui-refine/lenses.md)
(or use the `lens:` arg if provided). Read that lens's design-system anchors —
those are the principles a proposal under this lens must cite.

## Step 3 — Generate quota-capped proposals

Read the relevant capture artifacts with vision — the static screenshots (all 8,
or the `screen:` arg subset) for default lenses, or the motion filmstrip frames
under `docs/design/motion/<variant>/` for **L4** — read the lens's anchor
sections in `docs/design/design-system.md`, then generate candidates **strictly
through today's lens** — do not drift into other lenses' concerns.

- **Quota: at most 1–2 candidates — per run, total across both kinds**
  (design proposals + compliance gaps), **not per bucket.** The two-section
  digest (Step 6) groups survivors by kind; it does not raise the ceiling. Force
  ranking: "if you could change one thing under this lens, what and why." Quality
  via scarcity.
- **Every candidate must carry:** the design-system anchor (or named HIG / WCAG
  guideline) it advances, the screen(s) it concerns, and a concrete
  **before → after** — not a vague "make it nicer." A candidate that can't name
  an anchor or a concrete change is dropped here.

## Step 4 — Adversarial self-filter

For each surviving candidate, switch stance and try to **reject** it. Drop it
unless it survives every test:

- **Already by-design?** Does design-system.md or a `.claude/rules/` entry
  already prescribe the current behaviour deliberately?
- **Already covered — followed or violated?** Does the design system already
  address this? Split on what the screen *actually does* — this test has two
  opposite outcomes, and collapsing them is the bug that suppresses the
  best findings:
  - **Correctly follows the convention → drop.** Re-stating that a convention
    exists, when the UI already obeys it, is noise.
  - **Violates the convention → keep it as a *compliance gap*.** A verified
    divergence from a spec-determined value is the highest-value,
    highest-confidence finding — not a design proposal, but never a drop. (The
    dogfood's UR-001 § 5.11 violation is exactly this; the literal "already
    covered → drop" test would have suppressed it.) Route it to the
    **compliance-gap bucket** (Step 6). It MUST cite the *specific* violated
    anchor **and** the observed-vs-prescribed delta (the same before → after
    rigor Step 3 demands) — a compliance gap that can't show the delta is a
    re-derivation in disguise; drop it.
- **Subjective preference?** Is this taste rather than a principle-grounded
  improvement?
- **Out of scope?** Is it a Phase 3 feature? Check `docs/ROADMAP.md`
  § "Scope Decision Quick Reference" (item 3: "Is it a Phase 3 feature? → Don't
  do it"). Also drop anything that needs new product scope rather than refining
  what exists.
- **Would a maintainer say "considered, no"?** If a thoughtful maintainer would
  plausibly have already weighed and declined it, drop it (or note the
  counter-evidence honestly).

Only survivors proceed — *design proposals* and *compliance gaps* alike. Carry
each survivor's **kind** (`design-proposal` | `compliance-gap`) forward to
Steps 5–6.

## Step 5 — Dedup against the ledger

Read `docs/design/ui-refine/ledger.md`. Drop any survivor that restates an
existing row's **concept** (match on idea, not exact string) — regardless of that
row's status (`proposed` / `filed` / `rejected` / `deferred` / `done`). This is
the linchpin: it stops the same idea resurfacing every rotation. If everything
dedups away, that is a healthy outcome — write a digest that says "no new
proposals this run" and append nothing.

## Step 6 — Write the digest + append the ledger

1. **Digest** — write `docs/design/ui-refine/digests/YYYY-MM-DD-L<n>-<slug>.md`
   (date from `date +%F`). Rank the survivors, grouped into two labeled sections
   by kind (Step 4):
   - **Compliance gaps** (spec violations — fix in code) — each cites the
     violated anchor + the observed-vs-prescribed delta; its counter-evidence
     line reframes to "maybe the convention itself is wrong / maybe this is an
     intentional carve-out" (cf. UR-002, a real § 8 contrast finding that
     resolved *as* an intentional carve-out — a violation candidate is not
     automatically a defect).
   - **Design proposals** (judgment) — each carries the design-system anchor,
     a concrete before → after, **confidence**, and a **counter-evidence** line
     (Output Contract rule 2 — judgment output carries confidence + counter-evidence).
   Omit a section that is empty; if there are no survivors at all, record that
   explicitly.
2. **Ledger** — append one row per survivor to `ledger.md` with the next
   `UR-NNN` id, today's date, the lens, the screen, a one-line concept summary,
   status `proposed`, and the rationale in `note`. **Pin the kind in the row:** a
   compliance gap prefixes its `note` with `[compliance-gap]` (a design proposal
   needs no prefix), so the kind is visible to dedup (Step 5) and human triage —
   a digest-only kind would bypass the linchpin dedup memory. Keep ids ordered
   (newest last). **Do not commit or push** — leave the change in the working
   tree for the human (Safety boundary).
3. Report to the user: the digest path, the lens used, how many candidates were
   generated / filtered / deduped / surfaced, and a reminder that promotion
   (digest → issue + committing the ledger) is a manual step.
