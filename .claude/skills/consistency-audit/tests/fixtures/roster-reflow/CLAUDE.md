# Reflowed-roster fixture

The `roster-shape` sibling reflows the roster into a bullet list, which stops
matching the entry shape and is caught. This one is the reflow that still
*does* match: the same entries, rewrapped across two lines the way an editor
or a prose-wrapping tool would. Markdown renders it identically, so nothing
signals the change — and parsing only the first line would report every entry
below it as missing, at high confidence, because those ADRs exist.

The second line here wraps immediately after a separator, so it carries no
separator of its own. Counting only lines that re-match the entry shape misses
it; the roster's markdown paragraph is what has to be measured.

### ADR roster

001 Architecture overview · 002 Multi-platform strategy ·
003 Background execution

## Expected

Exactly one finding, naming the reflow — never one finding per ADR.

ADR-003 is on disk and in the roster but absent from INDEX.md. The roster axis
is unreadable here; the INDEX axis is not, and degrading one must not silence
the other.
