# code-health-audit — finding ledger

The cross-run dedup memory. Every finding that survives a run's Vet is appended
here. Before surfacing a finding, a run reads this ledger and **must not
re-surface** any finding already recorded **regardless of status** — including
ones already `filed` as issues (e.g. #1056/#1057) or `rejected`. This is the
linchpin mechanism in [README](README.md); without it, a periodic sweep re-floods
the human with the same findings — and re-files what is already an open issue.

**Dedup is by concept, not `file:line`.** Code drifts, so a finding's line offset
moves between runs; a line-exact match would let an already-tracked finding
resurface at a new location. Match on the `concept` fingerprint below.

**Lifecycle:** the skill *appends* rows but never commits or pushes. A human
commits the append, bundled with promoting a digest finding to an issue (see
[README](README.md) § Promotion / § Ledger lifecycle).

## Format

One row per finding, append-only. Columns:

| Column | Meaning |
|--------|---------|
| `id` | `CH-NNN`, monotonically increasing (next id = highest existing + 1, zero-padded to 3). |
| `date` | `YYYY-MM-DD` of the run that surfaced it. |
| `category` | `test-coverage` · `correctness` · `concurrency` · … (the finder category). |
| `concept` | **Stable fingerprint for dedup** — a short, location-independent description of the *defect idea* (e.g. `vote-tie-break diverges eliminate vs vote_winner`), NOT a `file:line`. This is the dedup key; it must survive code drift. |
| `anchor` | The `file:line` lead at surface time — for human navigation only, **never** the dedup key (it drifts). |
| `status` | `proposed` (in a digest, awaiting triage) · `filed (#N)` · `rejected` · `done`. |
| `note` | Rationale for `proposed`, the rejection reason, or the resolving PR. Empty for `filed`. |

## Ledger

| id | date | category | concept | anchor | status | note |
|----|------|----------|---------|--------|--------|------|
<!-- Appended by code-health-audit runs. Seeded empty — the two pilot bugs are
     already tracked as GitHub issues #1056/#1057, so they are recorded here as
     `filed` to prevent the first real run from re-surfacing them. -->
| CH-001 | 2026-07-12 | correctness | vote-tie-break diverges: EliminateHandler (name asc) vs vote_winner (name desc) | Engine/Phases/EliminateHandler.swift:18 | filed (#1056) | pilot find |
| CH-002 | 2026-07-12 | correctness | WordwolfJudgeLogic vote-tie winner non-deterministic (no secondary sort key) | Engine/ScoringLogic/WordwolfJudgeLogic.swift:25 | filed (#1057) | pilot find |
