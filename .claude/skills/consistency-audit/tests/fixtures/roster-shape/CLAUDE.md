# Reshaped-roster fixture

Negative control for the roster anchor's fail-open path. The section is still
declared, but the entries were reflowed into a bullet list, so the shape the
parser keys on no longer matches. It must report the shape change once —
never fall silent, and never flood one finding per ADR from an empty roster.

### ADR roster

- 001 Architecture overview
- 002 Multi-platform strategy
