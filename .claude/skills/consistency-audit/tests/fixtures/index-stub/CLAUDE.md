# Stub-index fixture

The `index-shape` sibling keeps ADR tokens in INDEX.md under a wrong heading
level. This one is the emptier reshape: a placeholder INDEX with no ADR token
at all. Requiring a token before reporting the shape change let exactly this
file through into a per-ADR flood, since every roster entry then reads as
missing from an index that parses zero headings.

### ADR roster

001 Architecture overview · 002 Multi-platform strategy

## Expected

Exactly one structural finding, never one per ADR.
