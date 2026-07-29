# Roster-runs-into-prose fixture

The roster is one complete line, but the sentence after it has no blank line
between, so markdown renders them as one paragraph. This check reads a single
entry line and cannot tell that sentence from a title that wrapped, so it
reports the paragraph rather than guessing — reading only the first line would
truncate the last entry's title into a confident wrong title mismatch.

### ADR roster

001 Architecture overview · 002 Multi-platform strategy
Titles are kept byte-identical to the INDEX headings.

## Expected

One structural finding whose text claims only what is true: the paragraph
spans two lines and the rest is unread. Never a per-ADR claim.
