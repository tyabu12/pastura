# Roster fixture

Exercises the three-way roster / INDEX / on-disk comparison. Four entries
drift, three stay silent.

## Reference Documents

| Document                     | Content                                          |
|------------------------------|--------------------------------------------------|
| `docs/decisions/ADR-006.md`  | Cloud API — reserved, not yet written            |

### ADR roster

Titles only; kept byte-identical to the INDEX headings.

001 Architecture overview · 003 Background execution · 006 Cloud API · 007 Focus mode · 016 Home redesign — bottom-tab IA · 099 Withdrawn experiment

## Expected

Silent: 001 (agrees everywhere), 006 (listed everywhere, no file, reserved
row present), 016 (its title carries an em dash of its own — splitting the
INDEX heading anywhere but the first separator corrupts it).

Firing: 002 (on disk and in the index, never appended here), 003 (on disk and
here, never appended to the index), 007 (title edited on one side only), 099
(here with no file and no reserved row).
