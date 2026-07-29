# Head-reflowed-roster fixture

The `roster-reflow` sibling wraps after the second entry, so the first line
keeps a separator and anchors the paragraph. This one wraps after the *first*,
and the trailing separator has had its space stripped — what every
whitespace-stripping editor does on save. The separator constant carries both
spaces, so `001 A ·` does not contain it: anchoring on an entry-shaped line
carrying a separator skips past line one entirely, measures the paragraph from
line two, finds a single line, and reports ADR-001 missing from a roster it is
the first entry of. Anchoring must walk back to the paragraph's own start.

### ADR roster

001 Architecture overview ·
002 Multi-platform strategy · 003 Background execution
