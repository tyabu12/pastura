# ui-refine — proposal ledger

The cross-run dedup **and rejection** memory. Every candidate a run *considered*
is appended here — not only the ones it surfaced. Before proposing, a run reads
this ledger and **must not re-surface** any proposal already recorded, with one
exception (`parked`, below). This is mechanism 1 (the linchpin) in
[README](README.md); without it, a periodic critique pass against a static UI
repeats itself every rotation.

**Lifecycle:** the skill *appends* rows but never commits or pushes. A human
commits the append, bundled with promoting a digest item to an issue (see
[README](README.md) § Promotion / § Ledger lifecycle). The skill's **one**
in-place exception is a `parked` row it wrote itself (§ Format).

## Format

One row per candidate, append-only (see the `parked` exception below). Columns:

| Column | Meaning |
|--------|---------|
| `id` | `UR-NNN`, monotonically increasing (next id = highest existing + 1, zero-padded to 3). |
| `date` | `YYYY-MM-DD` of the run that recorded it. |
| `lens` | `L1`…`L7` (the lens active that run). |
| `screen` | The tour screen it concerns (e.g. `01-home`), or `cross` for cross-screen. |
| `proposal` | One-line summary — enough to dedup against, not the full digest entry. |
| `status` | `proposed` (in a digest, awaiting triage) · `filed (#N)` · `rejected` · `parked` · `deferred` · `done`. |
| `note` | Rationale for `proposed`, or the rejection/deferral reason. Empty for `filed`/`done`. |

**Statuses split by who set them, and that split decides dedup:**

| `status` | Set by | Means | Suppresses a re-derived concept? |
|---|---|---|---|
| `proposed` | skill | surfaced in a digest, awaiting triage | yes |
| `rejected` | skill (adversarial filter) or human | judged and declined; `note` names the failing test | yes |
| `parked` | **skill only** | below the run's quota cut — **never judged**, only deferred | **no** |
| `filed (#N)` / `deferred` / `done` | human | promotion outcomes | yes |

**`parked` is the machine deferral and is deliberately NOT `deferred`.** They
would otherwise collide: `deferred` is a human "considered, not now" — a
judgment, so it suppresses — while `parked` records only that a quota ran out of
room that run. Distinguishing them by a `note` prefix alone would not work, since
a human setting `deferred` during promotion is never told to write one.

**In-place exception.** The skill may edit a `parked` row **it wrote itself**
when a later run re-derives the same concept: refresh `date`, and flip `status`
to `proposed` if it clears the quota that time. This keeps one deferred candidate
from accreting a duplicate row per rotation. No other row and no human-owned
field is ever machine-edited.

A new run appends rows with status `proposed`, `rejected` or `parked`. The human
later edits the `status`/`note` of existing rows during promotion. **Dedup
matches on the *concept*, not the exact string** — if a new candidate restates an
existing row's idea, it is a duplicate and must be dropped, unless that row is
`parked`.

**Finding kind (orthogonal to `status`).** A survivor is either a *design
proposal* (judgment) or a *compliance gap* — a verified divergence from a
spec-determined value (SKILL § Step 4). Kind is **not** a `status` value:
`status` is the lifecycle (`proposed`→`filed`→`done`), and a compliance gap
moves through it like any other finding. Record the kind in the row by prefixing
its `note` with `[compliance-gap]` (a design proposal needs no prefix), so the
kind stays visible to dedup and human triage instead of living only in the
gitignored digest.

**Note prefixes** are how a row says *why* it holds its status, and they compose
with the kind prefix above:

| Prefix | On | Meaning |
|---|---|---|
| `[compliance-gap]` | any status | the finding kind (above) |
| `[filter-drop: <test>]` | `rejected` | which adversarial-filter test rejected it (SKILL § Step 4) |
| `[quota]` | `parked` | truncated by the run's quota (SKILL § Step 6), not judged |

## Ledger

<!-- Append below. Keep newest-last so ids stay ordered. -->

| id | date | lens | screen | proposal | status | note |
|----|------|------|--------|----------|--------|------|
| UR-001 | 2026-06-24 | L3 | 05-gallery-detail | GalleryScenarioDetail nav title `.inline`→`.large` per § 5.11 | done | [compliance-gap] Fixed: added `.navigationBarTitleDisplayMode(.large)`; § 5.11 prose reconciled (table already correct). |
| UR-002 | 2026-06-24 | L1 | 01-home | List caption `--muted` ≈3.3:1 below § 8 4.5:1 | done | Resolved via § 8 carve-out: `--muted` quietude tier intentionally sub-AA for §1 voice; no code change (user kept muted over darkening). |
| UR-003 | 2026-06-24 | L5 | 07-results | `"%lld records"` not plural-aware (renders "1 records") | done | [compliance-gap] Fixed: callsite → `Text("\(count) records")` (Int-interp plural); en `variations.plural` one/other + ja single-form; `extractionState=manual` (key invisible to the CLI extract). Added i18n.md § Plurals + a catalog-structure test. |
