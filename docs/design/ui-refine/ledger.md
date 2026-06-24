# ui-refine — proposal ledger

The cross-run dedup memory. Every proposal that survives a run's adversarial
filter is appended here. Before proposing, a run reads this ledger and **must
not re-surface** any proposal already recorded — regardless of status. This is
mechanism 1 (the linchpin) in [README](README.md); without it, a periodic
critique pass against a static UI repeats itself every rotation.

**Lifecycle:** the skill *appends* rows but never commits or pushes. A human
commits the append, bundled with promoting a digest item to an issue (see
[README](README.md) § Promotion / § Ledger lifecycle).

## Format

One row per proposal, append-only. Columns:

| Column | Meaning |
|--------|---------|
| `id` | `UR-NNN`, monotonically increasing (next id = highest existing + 1, zero-padded to 3). |
| `date` | `YYYY-MM-DD` of the run that surfaced it. |
| `lens` | `L1`…`L7` (the lens active that run). |
| `screen` | The tour screen it concerns (e.g. `01-home`), or `cross` for cross-screen. |
| `proposal` | One-line summary — enough to dedup against, not the full digest entry. |
| `status` | `proposed` (in a digest, awaiting triage) · `filed (#N)` · `rejected` · `deferred` · `done`. |
| `note` | Rationale for `proposed`, or the rejection/deferral reason. Empty for `filed`/`done`. |

A new run appends rows with status `proposed`. The human later edits the
`status`/`note` of existing rows during promotion. **Dedup matches on the
*concept*, not the exact string** — if a new candidate restates an existing
row's idea (any status), it is a duplicate and must be dropped.

## Ledger

<!-- Append below. Keep newest-last so ids stay ordered. -->

| id | date | lens | screen | proposal | status | note |
|----|------|------|--------|----------|--------|------|
| _(empty — first run starts at UR-001)_ | | | | | | |
