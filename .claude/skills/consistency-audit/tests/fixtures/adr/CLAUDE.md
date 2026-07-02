# ADR-reference fixture

Exercises the dangling_adr detector: two references fire, three stay silent.
Prose avoids the shared per-line marker words except on the two lines that
intentionally carry a marker.

## Reference Documents

| Document                     | Content                                                       |
|------------------------------|---------------------------------------------------------------|
| `docs/decisions/ADR-001.md`  | Architecture overview                                         |
| `docs/decisions/ADR-006.md`  | Cloud API (Phase 3; reserved — not yet written; see ADR-005 §7.5) |

## Must fire

- A dangling mention of ADR-099 with no matching file is a finding.
- A plain-body mention of ADR-005 is a finding — it shows up only inside the
  ADR-006 row's description cell, and first-cell keying keys on 006, so a bare
  mention in a description cannot silence a different number.

## Must NOT fire

- A plain-body mention of ADR-006 is absorbed by the canonical set built from
  the table above; this line carries no inline marker, so the set path (not
  the per-line guard) is what keeps it quiet.
- A mention of ADR-001 resolves to its file under docs/decisions.
- An inline mention of ADR-098 (reserved — not yet written) is dropped by the
  shared per-line guard even though no table row lists it.

## Fenced block (must be skipped)

```
A fenced mention of ADR-097 stays silent.
```
