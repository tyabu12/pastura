# Reshaped-reservation fixture

Negative control for `load_reserved_adrs`' table-row shape requirement. The
reservation entry below carries the marker words but is prose, not a `|` row
with a `docs/decisions/ADR-NNN.md` first cell — so the parser must NOT absorb
it, and the plain-body mention further down must be flagged. Modelled on the
real regression: PR #1310 commit 0ed05a3f left the project's CLAUDE.md in
exactly this shape, and every reference to the intentionally-absent ADR became
a dangling false positive.

The sibling `adr` fixture asserts the same ADR stays *silent* when the row IS
in table shape. That assertion alone proves nothing about the shape
requirement — only this fixture can redden if the requirement is dropped.

## Reference Documents

| Document                     | Content               |
|------------------------------|-----------------------|
| `docs/decisions/ADR-001.md`  | Architecture overview |

**ADR-006 is reserved but unwritten** — Cloud API implementation details
(Phase 3). A gap in the sequence, not a free slot.

## Must fire

- A plain-body mention of ADR-006 carries no marker of its own, and no table
  row absorbs it, so it is a dangling reference.

## Must NOT fire

- A mention of ADR-001 resolves to its file under docs/decisions.
