# Deleted-reservation fixture

The sibling `adr-reservation-reshaped` fixture covers the case where the
reservation is still stated in this file but in a shape the parser cannot see.
This one covers the next compaction step: the statement is gone from here
entirely, so scanning this file for marker words finds nothing to complain
about. `docs/decisions/INDEX.md` still lists the ADR and no file backs it,
which is what the check keys on instead.

## Reference Documents

| Document                     | Content               |
|------------------------------|-----------------------|
| `docs/decisions/ADR-001.md`  | Architecture overview |

## Must NOT fire

- A mention of ADR-001 resolves to its file under docs/decisions.
