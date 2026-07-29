# Reshaped-index fixture

The mirror of `roster-shape`: the roster parses fine, but INDEX.md still
references ADRs while no `## ADR-NNN — <title>` heading matches. Comparing the
roster against an empty index would report every entry as missing, so the
check reports the shape change once instead.

### ADR roster

001 Architecture overview · 002 Multi-platform strategy
