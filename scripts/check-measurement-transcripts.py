#!/usr/bin/env python3
r"""Guard: the contrast figures `docs/**` transcribes and the ones
`DesignTokensTests+MutedTranscript` pins are the **same numbers** (#1488).

These doc faces copy figures the fixture computes, and nothing compared them:
`muted-application-audit.md` §3.1 (twelve opaque grounds + the derived span) and
§3.2 (five wash rows), `ADR-028.md` § Amendment 2026-08-15 (a four-row copy of
that wash table) and § Amendment 2026-08-13 (the span), and `design-system.md`
§8 (the span again). `muted-application-audit.md` § "Regenerating the ratio
tables" is the reader-facing procedure.

Directions differ by face, deliberately:

- §3.1 and §3.2 are **bijections** with the pins. One-way containment lets an
  unmatched row drop out of the comparison silently.
- ADR-028's table is a **subset**: four of the five rows (no
  `HighlightShareCard`), worded differently for `ReportSheet`. Every ADR row
  must match a pin; a pin with no ADR row is correct.
- §5's site column is **membership only** — see `compare_membership`.

The span sentence is anchored **structurally**: within the section, the block
that names `DesignTokensTests+MutedTranscript` is the one claiming the fixture
pins the twelve, and the span literal is read out of it. Searching for the
span's own low end would find what it was told to find.

Anchors all assert rather than degrade — a renumbered heading, a renamed
declaration, a changed table header, an **empty extracted set** or an unreadable
input each raises, instead of collapsing into an empty-vs-empty "equal" pass.

**No colour arithmetic lives here.** `design-system.md` §8 warns that a
hand-rolled script quantizing channels to 0–255 diverges from the fixture — and
that is exactly the script someone would write next. Everything below is string
and decimal comparison; the fixture stays the only thing that composites.

**Green certifies the arithmetic only** — not that a doc row describes the right
site, that the site still paints the wash its arm composites, or that a ground
read off the view hierarchy is correct. §3.2's own corrections are all of that
kind and a pin would have caught none of them.

**Don't replace this with a tree-wide grep for duplicated literals.** It cannot
stop firing (`ds/README.md` orders `ds/*.html` to mirror `design-system.md`, and
ADR-028 orders measurements into an amendment), it cannot tell a **checked**
transcript from an unchecked copy, and being value-keyed it hits only copies
still in **sync** — going quiet on exactly the rotted copy it was wanted for
(ADR-028 § "A count mirror that a count-keyed sweep structurally cannot find").

It reads **blocks, not sections** — the anchored tables, the §5 site tables, and
the one block per span section that names the fixture. So a figure restated in
prose a few lines away stays hand-kept. **That list is printed, not maintained
here** — `--residue`; four hand-written versions of it were wrong. #1496 carries
the open judgments, and the ledger section above has the report's caveats.

Trigger paths live in `scripts/measurement-transcript-precommit-gate.sh`. That
regex and this module's `*_PATH` constants are **two lists that can drift** — a
file added here and not there is a silent local skip — so `--self-test` asserts
`INPUT_PATHS` is covered by that regex, with a decoy arm dropping one
alternative so the positive arm cannot pass vacuously.

Usage:
    python3 scripts/check-measurement-transcripts.py --self-test
    python3 scripts/check-measurement-transcripts.py --check
    python3 scripts/check-measurement-transcripts.py --residue   # report-only
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Repo-relative for display; `_read` resolves against the repo root so a run from
# a subdirectory reads the right files instead of raising.
REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_PATH = Path("Pastura/PasturaTests/Views/DesignTokensTests+MutedTranscript.swift")
LEDGER_PATH = Path("docs/design/muted-application-audit.md")
ADR_PATH = Path("docs/decisions/ADR-028.md")
DESIGN_SYSTEM_PATH = Path("docs/design/design-system.md")
GATE_PATH = Path("scripts/measurement-transcript-precommit-gate.sh")
CHECKER_PATH = Path("scripts/check-measurement-transcripts.py")

# Every path this module reads, plus its own — `CHECKER_PATH` is never read and
# `GATE_PATH` only under `--self-test`; both are listed because editing either
# must re-run the gate. `--self-test` asserts the gate's `TRIGGER` covers them.
INPUT_PATHS = (
    FIXTURE_PATH,
    LEDGER_PATH,
    ADR_PATH,
    DESIGN_SYSTEM_PATH,
    GATE_PATH,
    CHECKER_PATH,
)

GATE_TRIGGER_LINE = re.compile(r"^TRIGGER='(?P<pattern>.+)'$", re.MULTILINE)

FIXTURE_NAME = "DesignTokensTests+MutedTranscript"

OPAQUE_DECL = "private static let opaqueGroundPins"
WASH_DECL = "private static let washRowPins"
# Read only by `--residue`: the gate itself never compares the brackets to a doc.
BRACKET_DECL = "private static let ruleWashBracketPins"
# `("name", 1.234)` — the shared shape of the ratio-keyed pin arrays. That value,
# and every example figure below, is synthetic on purpose: a real pinned one
# written here would be one more hand-kept copy.
SWIFT_RATIO_PIN = re.compile(r'\(\s*"([^"]+)"\s*,\s*([0-9]+(?:\.[0-9]+)?)\s*\)')
SWIFT_WASH_PIN = re.compile(
    r'WashRowPin\(\s*site:\s*"([^"]+)"\s*,\s*'
    r"light:\s*\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\)\s*,\s*"
    r"dark:\s*\(\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*\)\s*\)"
)

# Any list item at any indent — terminates the preceding block's continuations.
LIST_ITEM = re.compile(r"^[ \t]*([-*+]|[0-9]+\.)[ \t]")
BACKTICKED = re.compile(r"`([^`]+)`")
LEADING_IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
DECIMAL = re.compile(r"[0-9]+\.[0-9]+")
# Wider than today's text on purpose (the docs use `–` and `〜`). The ASCII
# hyphen is the member most likely to produce a false red: a hyphenated numeric
# pair in an anchored block (`3.1-3.2`) reads as a second span.
RANGE = re.compile(r"([0-9]+\.[0-9]+)\s*[–—〜～~-]\s*([0-9]+\.[0-9]+)")
WASH_TABLE_HEADER = re.compile(r"^\|\s*Site\s*\|.*\blight\b.*\bdark\b", re.IGNORECASE)
OPAQUE_TABLE_HEADER = re.compile(r"^\|\s*Light ground\s*\|", re.IGNORECASE)

# Section anchors, named once so `collect` and the self-test cannot drift into
# two spellings of the same pattern.
#
# The two terminators differ, and swapping them is not caught by a named arm —
# only by the SHAPE of the synthetic fixtures. The ledger's faces are `###`
# subsections, so ANY heading ends them (`^#{2,3} ` would let a future `#### `
# extend the slice). The ADR's faces are `##` amendments that legitimately
# CONTAIN `###` subsections — the wash table sits under one — so there the
# terminator must stay `^## ` or the slice ends before the table.
#
# `NEXT_SUBSECTION` also matches a `# comment` inside a fenced code block, which
# this corpus has (ADR-028 §Context). It fails CLOSED — early truncation raises
# the missing-header anchor — but a fence inside §3.1/§3.2 would need handling.
NEXT_SUBSECTION = re.compile(r"^#{1,6} ")
NEXT_SECTION = re.compile(r"^## ")
LEDGER_31 = re.compile(r"^### 3\.1\b")
LEDGER_32 = re.compile(r"^### 3\.2\b")
ADR_WASHES = re.compile(r"^## Amendment 2026-08-15\b")
ADR_SPAN = re.compile(r"^## Amendment 2026-08-13 — the quietude tier\b")
DESIGN_SYSTEM_8 = re.compile(r"^## 8\.")

# ADR-028's copy carries four of the five rows. Naming the missing one keeps the
# omission an assertion rather than a hole — `compare_wash` reddens both when a
# named row appears and when an unnamed one goes missing.
ADR_OMITS = frozenset({"HighlightShareCard"})

LEDGER_5 = re.compile(r"^## 5\. ")
LEDGER_5_TABLE = re.compile(r"^\|\s*Site \(file · symbol\)\s*\|")
# The `light/dark` column, 0-indexed, of the §5 site tables.
LEDGER_5_RATIO_CELL = 2
LEDGER_5_CELLS = 5
# Three-digit precision, for deciding whether a §5 table carries *ratios* at all.
# Plain `DECIMAL` is too loose: the `Tally` table's "WCAG 1.4.11" yields `1.4`
# and would make it look like an unchecked ratio table. Blind spot: a §5 table
# whose header drifts AND whose figures are all at another precision (`3.03`,
# `3.0291`) is exempted silently. Extraction below still uses `DECIMAL`, so only
# the drifted-header case is uncovered.
RATIO3 = re.compile(r"\b[0-9]+\.[0-9]{3}\b")


class AnchorError(Exception):
    """An extraction anchor stopped matching — the gate cannot judge."""


def _read(path: Path) -> str:
    """Read a tracked input, or raise `AnchorError` naming both edit sites.

    A rename is the loudest way this fires: the gate's `TRIGGER` stops matching
    the new path too, so the local gate skips silently. A bare
    `FileNotFoundError` would surface that as a traceback instead.
    """
    try:
        return (REPO_ROOT / path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise AnchorError(
            f"{path}: cannot read it ({exc}). If it was renamed, update "
            "BOTH this checker's path constant AND the TRIGGER regex in "
            "scripts/measurement-transcript-precommit-gate.sh — otherwise the "
            "local gate stops matching the new path and skips silently."
        ) from exc


def gate_trigger(text: str) -> str:
    """The gate's `TRIGGER` regex, or `AnchorError` if it stopped being findable.

    Anchored on the assignment line rather than on any path inside it: searching
    for a path would find what it was told to find, which is the thing under
    test here.
    """
    match = GATE_TRIGGER_LINE.search(text)
    if match is None:
        raise AnchorError(
            f"{GATE_PATH}: no `TRIGGER='...'` assignment on a line of its own. "
            "That assignment is what this checker reads to confirm every file it "
            "reads also fires the gate; re-anchor it or this coverage arm is "
            "measuring nothing."
        )
    return match.group("pattern")


def uncovered_inputs(trigger: str) -> list[str]:
    """Input paths the gate's `TRIGGER` does NOT match — editing one of those
    skips the gate locally, silently and in the permissive direction.
    """
    pattern = re.compile(trigger)
    return [str(path) for path in INPUT_PATHS if not pattern.search(str(path))]


def canonical(value: str) -> str:
    """A decimal at the docs' printed precision, so `1.2` and `1.200` agree."""
    return f"{float(value):.3f}"


def _section_lines(
    text: str, start: re.Pattern[str], nxt: re.Pattern[str], where: str
) -> range:
    """One anchored section's 0-based line range, or `AnchorError`.

    Split out of `section` so `--residue` can subtract by line number.
    """
    lines = text.splitlines()
    begin = None
    for i, line in enumerate(lines):
        if start.match(line):
            begin = i
            break
    if begin is None:
        raise AnchorError(f"{where}: the section heading is gone — renumbered, renamed or moved.")
    end = len(lines)
    for i in range(begin + 1, len(lines)):
        if nxt.match(lines[i]):
            end = i
            break
    return range(begin, end)


def section(text: str, start: re.Pattern[str], nxt: re.Pattern[str], where: str) -> list[str]:
    """The lines of one anchored section, or `AnchorError`."""
    span = _section_lines(text, start, nxt, where)
    return text.splitlines()[span.start : span.stop]


def logical_blocks(lines: list[str]) -> list[str]:
    """Paragraphs and list items, each joined with its continuation lines.

    The span sentence crosses a hard wrap in two of its three faces. Table rows
    and headings break a block, and `LIST_ITEM` breaks one per bullet: without
    that, `design-system.md` §8's consecutive bullets fuse and the span anchor
    picks up an unrelated bullet's range.
    """
    blocks: list[str] = []
    current: list[str] = []

    def flush() -> None:
        if current:
            blocks.append(" ".join(current))
            current.clear()

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("|"):
            flush()
            continue
        if LIST_ITEM.match(line):
            flush()
        current.append(stripped)
    flush()
    return blocks


def logical_blocks_with_offsets(lines: list[str]) -> list[tuple[str, list[int]]]:
    """``logical_blocks``, each block paired with the 0-based lines it spans.

    Deliberately mirrors `logical_blocks`: `--residue` must subtract exactly what
    the gate reads. Subtracting "the line naming the fixture" rather than "the
    block naming the fixture" reports the line carrying the FIGURE as unguarded
    while the gate is comparing it.
    """
    blocks: list[tuple[str, list[int]]] = []
    current: list[str] = []
    offsets: list[int] = []

    def flush() -> None:
        if current:
            blocks.append((" ".join(current), list(offsets)))
            current.clear()
            offsets.clear()

    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("|"):
            flush()
            continue
        if LIST_ITEM.match(line):
            flush()
        current.append(stripped)
        offsets.append(i)
    flush()
    return blocks


def table_rows(lines: list[str], header: re.Pattern[str], where: str) -> list[list[str]]:
    """Body cells of the one table whose header row matches, or `AnchorError`."""
    start = None
    for i, line in enumerate(lines):
        if header.match(line.strip()):
            start = i
            break
    if start is None:
        raise AnchorError(f"{where}: no table whose header row matches — the columns changed.")
    rows: list[list[str]] = []
    for line in lines[start + 1 :]:
        stripped = line.strip()
        if not stripped.startswith("|"):
            break
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if all(set(cell) <= set("-: ") for cell in cells):
            continue
        rows.append(cells)
    if not rows:
        raise AnchorError(f"{where}: the table has a header but no body rows.")
    return rows


# --- extraction: the fixture ------------------------------------------------


def _decl_block(text: str, decl: str, where: str) -> str:
    """The declaration's lines, joined, from its opening to the `]` at its own
    indentation.

    Joined rather than read per line: swift-format wraps a long literal, and a
    wrapped `WashRowPin(` read per line vanishes — failing with the *inverted*
    diagnosis ("the docs name a row the fixture lacks") and sending the author to
    edit the wrong file.
    """
    lines = text.splitlines()
    begin = None
    for i, line in enumerate(lines):
        if decl in line:
            begin = i
            break
    if begin is None:
        raise AnchorError(f"{where}: no '{decl}' declaration — the pins were renamed or moved.")
    indent = len(lines[begin]) - len(lines[begin].lstrip())
    for i in range(begin + 1, len(lines)):
        stripped = lines[i].strip()
        if not stripped:
            continue
        here = len(lines[i]) - len(lines[i].lstrip())
        if here > indent:
            continue
        if here == indent and stripped == "]":
            return "\n".join(lines[begin : i + 1])
        # Anything else at or outside the declaration's own indentation means the
        # closer is gone. Scanning past it would run into the NEXT declaration and
        # silently extract its rows as these — the two pin arrays sit one after
        # the other, so that is a live hazard rather than a hypothetical one.
        break
    raise AnchorError(f"{where}: could not find the closing ']' of '{decl}' at its indentation.")


def fixture_ratio_pins(text: str) -> dict[str, str]:
    """`opaqueGroundPins` as `{ground name: ratio}`."""
    block = _decl_block(text, OPAQUE_DECL, str(FIXTURE_PATH))
    pins = {name: canonical(ratio) for name, ratio in SWIFT_RATIO_PIN.findall(block)}
    if not pins:
        raise AnchorError(
            f"{FIXTURE_PATH}: '{OPAQUE_DECL}' yielded no `(\"name\", ratio)` rows — "
            "the pin shape changed, or the array was emptied."
        )
    return pins


def fixture_wash_pins(text: str) -> dict[str, tuple[tuple[str, str], tuple[str, str]]]:
    """`washRowPins` as `{site: ((light min, light max), (dark min, dark max))}`."""
    block = _decl_block(text, WASH_DECL, str(FIXTURE_PATH))
    pins = {
        site: ((canonical(lo), canonical(hi)), (canonical(dlo), canonical(dhi)))
        for site, lo, hi, dlo, dhi in SWIFT_WASH_PIN.findall(block)
    }
    if not pins:
        raise AnchorError(
            f"{FIXTURE_PATH}: '{WASH_DECL}' yielded no `WashRowPin(...)` rows — "
            "the pin shape changed, or the array was emptied."
        )
    return pins


# --- extraction: the docs ---------------------------------------------------


def _opaque_row_cells(lines: list[str], where: str) -> list[tuple[tuple[str, str], ...]]:
    """§3.1's rows as `((light name, light ratio), (dark name, dark ratio))`.

    Each row carries a light pair and a dark pair, and the ratio cells carry
    annotations (`← §8's calibration point`, `**1.234**`), so the first decimal
    in the cell is the figure and the rest is prose.

    Shared by the two public readers so they cannot drift into two parses of one
    table — and so `ledger_opaque_pairs` inherits every anchor below rather than
    restating them.
    """
    rows = table_rows(lines, OPAQUE_TABLE_HEADER, where)
    parsed: list[tuple[tuple[str, str], ...]] = []
    for cells in rows:
        # Exact, not a floor: an inserted column shifts the ratio cells, and a
        # `< 4` floor would then read the wrong cell's figure and blame the
        # figures rather than the columns.
        if len(cells) != 4:
            raise AnchorError(f"{where}: a §3.1 row has {len(cells)} cells, expected 4.")
        row: list[tuple[str, str]] = []
        for name_cell, ratio_cell in ((cells[0], cells[1]), (cells[2], cells[3])):
            name = BACKTICKED.search(name_cell)
            ratio = DECIMAL.search(ratio_cell)
            if not name or not ratio:
                raise AnchorError(
                    f"{where}: a §3.1 row is not `name` + ratio — got "
                    f"{name_cell!r} / {ratio_cell!r}."
                )
            row.append((name.group(1), canonical(ratio.group(0))))
        parsed.append(tuple(row))
    return parsed


def ledger_opaque_rows(lines: list[str], where: str) -> dict[str, str]:
    """§3.1's twelve grounds as `{ground name: ratio}`, both columns flattened."""
    rows = _opaque_row_cells(lines, where)
    found = {name: ratio for row in rows for name, ratio in row}
    # A repeated ground name would OVERWRITE, and the set-based comparison
    # downstream is blind to a multiset defect — a stale duplicate row above a
    # correct one would pass. `table_rows` covers the empty case. This also
    # covers `ledger_opaque_pairs`' disjointness: a name in both columns lands
    # here as one key for two slots.
    if len(found) != 2 * len(rows):
        raise AnchorError(
            f"{where}: {len(rows)} rows yielded only {len(found)} distinct grounds — "
            "a ground name is repeated, and the duplicate would silently win."
        )
    return found


def ledger_opaque_pairs(lines: list[str], where: str) -> dict[str, str]:
    """§3.1's rows as `{light ground: dark ground}` — the pairing itself.

    **§3.1 is the only source of this pairing**, and that is a residual rather
    than a choice. `opaqueGroundPins` is a flat `[(name, ratio)]` carrying no
    pair structure; its order differs from this table's; and reading either by
    array index is what that array's own doc comment forbids. So nothing above
    §3.1 can adjudicate *which* dark ground answers a given light one, and this
    reader asserts nothing beyond `_opaque_row_cells`' anchors.

    What does catch a swapped pairing is §5 consuming it — `compare_site_rows`
    resolves a §5 row's dark figure through this map, so the three pairs §5
    names (`screenBackground`, `bubbleBackground`, `page`) redden on a swap and
    a wholesale column swap raises there as an unknown ground. The other three
    (`whisperBubble`, `promoBackground`, `mossSoft`) stay unguarded as a
    pairing; #1496 records that residual rather than closing it.
    """
    rows = _opaque_row_cells(lines, where)
    # Runs `ledger_opaque_rows`' duplicate anchor for its side effect: without
    # it a name repeated across the two columns would build a pairing that
    # silently loses a row.
    ledger_opaque_rows(lines, where)
    return {light[0]: dark[0] for light, dark in rows}


def _interval(cell: str, where: str) -> tuple[str, str]:
    """A wash cell: either `d.ddd` (a point) or `d.ddd–d.ddd` (a range)."""
    span = RANGE.search(cell)
    if span:
        return canonical(span.group(1)), canonical(span.group(2))
    point = DECIMAL.search(cell)
    if not point:
        raise AnchorError(f"{where}: a wash cell carries no figure — got {cell!r}.")
    return canonical(point.group(0)), canonical(point.group(0))


Interval = tuple[str, str]
WashRows = dict[str, tuple[Interval, Interval]]


def wash_table_rows(lines: list[str], where: str) -> WashRows:
    """A `| Site | … | light | dark |` table as `{site: (light, dark)}`.

    The site key is the leading identifier of the cell's first backticked token,
    so both spellings the two faces use resolve to the same key:
    `` `ResultsView.pillBackground(.pending)` `` and `` `ResultsView` `.pending`
    pill `` both key on `ResultsView`.

    Because the key is a **truncation**, two rows on the same view collapse onto
    one entry and the earlier one's figures are never compared — live rather than
    defensive: §3.2 is expected to grow and `ResultsView` already ships a second
    pill state.
    """
    rows = table_rows(lines, WASH_TABLE_HEADER, where)
    found: dict[str, tuple[tuple[str, str], tuple[str, str]]] = {}
    for cells in rows:
        # Exact, not a floor — see `ledger_opaque_rows`.
        if len(cells) != 4:
            raise AnchorError(f"{where}: a wash row has {len(cells)} cells, expected 4.")
        token = BACKTICKED.search(cells[0])
        if not token:
            raise AnchorError(
                f"{where}: a wash row's Site cell names no `site` — got {cells[0]!r}."
            )
        key = LEADING_IDENTIFIER.match(token.group(1))
        if not key:
            raise AnchorError(f"{where}: a wash row's Site token is not identifier-shaped.")
        found[key.group(0)] = (_interval(cells[2], where), _interval(cells[3], where))
    if len(found) != len(rows):
        raise AnchorError(
            f"{where}: {len(rows)} rows collapsed onto {len(found)} site keys — two "
            "rows share a leading identifier, so one row's figures would never be "
            "compared. Give the table a key the truncation keeps distinct."
        )
    # Empty-set guard lives in `table_rows` — see `ledger_opaque_rows`.
    return found


def wash_row_grounds(lines: list[str], where: str) -> dict[str, str]:
    """A wash table's `Wash over ground` column as `{ground token: site key}`.

    The ground token is the first backticked token of `cells[1]` — `mossDark@0.10`
    out of `` `mossDark@0.10` over `screenBackground` / `nightBackground` ``. That
    cell is prose past the token (it names the grounds composited under, and one
    row says "over an unknown ground — see below"), so the token is the only part
    two faces spell identically.

    Keyed **ground → site**, the direction §5 needs: a §5 row names the wash it
    sits on, not the §3.2 row label. Site-keyed would be wrong outright — §5 has
    eight `ResultsView` rows and only one of them is the wash.

    Nothing read this cell before (#1496). Two anchors, both raising: a cell with
    no backticked token, and two rows sharing a token — the second would collapse
    onto one entry and send every §5 row on that wash to the surviving row's
    figures.
    """
    rows = table_rows(lines, WASH_TABLE_HEADER, where)
    found: dict[str, str] = {}
    for cells in rows:
        # Exact, not a floor — see `_opaque_row_cells`.
        if len(cells) != 4:
            raise AnchorError(f"{where}: a wash row has {len(cells)} cells, expected 4.")
        site = BACKTICKED.search(cells[0])
        if not site:
            raise AnchorError(
                f"{where}: a wash row's Site cell names no `site` — got {cells[0]!r}."
            )
        key = LEADING_IDENTIFIER.match(site.group(1))
        if not key:
            raise AnchorError(f"{where}: a wash row's Site token is not identifier-shaped.")
        ground = BACKTICKED.search(cells[1])
        if not ground:
            raise AnchorError(
                f"{where}: a wash row names no `wash` ground in its ground cell — "
                f"got {cells[1]!r}. §5 joins on that token."
            )
        if ground.group(1) in found:
            raise AnchorError(
                f"{where}: two wash rows share a ground token ({ground.group(1)!r}) — "
                "§5 joins on it, so one row's figures would never be reached."
            )
        found[ground.group(1)] = key.group(0)
    # Empty-set guard lives in `table_rows` — see `ledger_opaque_rows`.
    return found


def span_in(lines: list[str], where: str) -> tuple[str, str]:
    """The span the anchored block states, as `(low, high)`.

    Anchored on the block that names the fixture, never on the value itself — a
    value-keyed search finds what it was told to find.
    """
    blocks = [block for block in logical_blocks(lines) if FIXTURE_NAME in block]
    if not blocks:
        raise AnchorError(
            f"{where}: no paragraph or bullet in this section names "
            f"`{FIXTURE_NAME}`. That block is the span's anchor — if the sentence "
            "moved, repoint this checker's section anchor rather than deleting it."
        )
    spans = [match.groups() for block in blocks for match in RANGE.finditer(block)]
    if not spans:
        raise AnchorError(
            f"{where}: the block naming `{FIXTURE_NAME}` states no `low–high` span."
        )
    if len(set(spans)) != 1:
        raise AnchorError(f"{where}: the anchored block states more than one span: {spans}.")
    low, high = spans[0]
    return canonical(low), canonical(high)


# --- comparison -------------------------------------------------------------


def ledger_site_ratios(lines: list[str], where: str) -> list[tuple[str, str]]:
    """Every decimal in the §5 site tables' `light/dark` column, with its row label.

    §5 spans five sub-tables, so this walks all of them rather than reusing
    `table_rows`, which stops at the first. Two anchors, both raising:

    * a table inside §5 that carries decimals but whose header row does **not**
      match — a renamed or reordered column would otherwise drop that whole
      sub-table out of the comparison while the run stayed green. The `Tally`
      table is exempt by carrying no decimals, which is a property of the text
      rather than a name this checker has to keep in sync.
    * an empty extraction, so an emptied §5 cannot pass by agreeing with nothing.
    """
    found: list[tuple[str, str]] = []
    unmatched: list[str] = []
    i = 0
    while i < len(lines):
        if not lines[i].strip().startswith("|"):
            i += 1
            continue
        header = lines[i]
        body: list[str] = []
        i += 1
        while i < len(lines) and lines[i].strip().startswith("|"):
            body.append(lines[i])
            i += 1
        decimals_here = any(RATIO3.search(row) for row in body)
        if not LEDGER_5_TABLE.match(header.strip()):
            if decimals_here:
                unmatched.append(header.strip()[:60])
            continue
        for row in body:
            cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
            if all(set(cell) <= set("-: ") for cell in cells):
                continue
            if len(cells) != LEDGER_5_CELLS:
                raise AnchorError(
                    f"{where}: a row has {len(cells)} cells, expected {LEDGER_5_CELLS} — "
                    f"a column was inserted or removed: {row.strip()[:60]}"
                )
            label = cells[0]
            for value in DECIMAL.findall(cells[LEDGER_5_RATIO_CELL]):
                found.append((label, canonical(value)))
    if unmatched:
        raise AnchorError(
            f"{where}: {len(unmatched)} table(s) carry ratios but their header row no "
            f"longer matches, so they would go unchecked: {unmatched}"
        )
    if not found:
        raise AnchorError(
            f"{where}: no ratio cell yielded a decimal — the column moved, or the "
            "tables did. An empty extraction must not agree with an empty pin set."
        )
    return found


def compare_membership(
    found: list[tuple[str, str]], pool: set[str], where: str
) -> list[str]:
    """Every §5 ratio must be one the fixture computes somewhere.

    **Membership, not a bijection.** §5 quantifies its ground freely
    ("`screenBackground` or `bubbleBackground`", "same", "worst"), so deciding
    which pin a row *ought* to carry is a judgment — #1496 holds that open.
    Membership still catches a figure hand-carried into §5 that no longer matches
    anything the fixture computes; it does NOT catch a row carrying the wrong
    pin's value.
    """
    problems = []
    for label, value in sorted(set(found)):
        if value not in pool:
            problems.append(
                f"{where}: `{label}` reads {value}, which is not any figure the fixture "
                "pins — a ground was retuned and this row was not re-recorded, or the row "
                "names a ratio nothing computes."
            )
    return problems


def compare_ratios(doc: dict[str, str], pins: dict[str, str], where: str) -> list[str]:
    """Bijection + per-value comparison."""
    problems = []
    for name in sorted(set(doc) - set(pins)):
        problems.append(f"{where}: `{name}` is transcribed but is not a pin — drop it or pin it.")
    for name in sorted(set(pins) - set(doc)):
        problems.append(f"{where}: `{name}` is pinned but is not transcribed — add the row.")
    for name in sorted(set(doc) & set(pins)):
        if doc[name] != pins[name]:
            problems.append(
                f"{where}: `{name}` reads {doc[name]}, the fixture computes {pins[name]}."
            )
    return problems


def compare_wash(
    doc: dict[str, tuple[tuple[str, str], tuple[str, str]]],
    pins: dict[str, tuple[tuple[str, str], tuple[str, str]]],
    where: str,
    omits: frozenset[str] | set[str],
) -> list[str]:
    """Per-row comparison. `omits` names the pins this face deliberately lacks.

    A **set** rather than a subset flag: a flag has no cardinality floor, so the
    ADR table could shrink to a single row and stay green. Naming the omission
    also reddens if `HighlightShareCard` is added there without updating this
    checker.
    """
    problems = []
    for site in sorted(set(doc) - set(pins)):
        problems.append(f"{where}: `{site}` is transcribed but is not a pin — drop it or pin it.")
    missing = set(pins) - set(doc)
    for site in sorted(missing - omits):
        problems.append(f"{where}: `{site}` is pinned but is not transcribed — add the row.")
    for site in sorted(omits - set(pins)):
        problems.append(
            f"{where}: `{site}` is recorded here as deliberately omitted, but no pin has "
            "that name — it was renamed or removed. Update this checker's omission set, "
            "not the doc."
        )
    for site in sorted((omits & set(pins)) - missing):
        problems.append(
            f"{where}: `{site}` is recorded here as deliberately omitted, but the face "
            "now carries it — drop it from this checker's omission set."
        )
    for site in sorted(set(doc) & set(pins)):
        for appearance, got, want in (
            ("light", doc[site][0], pins[site][0]),
            ("dark", doc[site][1], pins[site][1]),
        ):
            if got != want:
                problems.append(
                    f"{where}: `{site}` {appearance} reads {got[0]}–{got[1]}, "
                    f"the fixture computes {want[0]}–{want[1]}."
                )
    return problems


def compare_span(got: tuple[str, str], pins: dict[str, str], where: str) -> list[str]:
    """The span is derived, not measured: it is the min and max of the twelve."""
    ratios = sorted(pins.values(), key=float)
    want = (ratios[0], ratios[-1])
    if got != want:
        return [
            f"{where}: the span reads {got[0]}–{got[1]}, but the pinned grounds "
            f"run {want[0]}–{want[1]}."
        ]
    return []


# --- the real tree ----------------------------------------------------------


def collect(
    fixture: str,
    ledger: str,
    adr: str,
    design_system: str,
    adr_omits: frozenset[str] = ADR_OMITS,
) -> list[str]:
    """Every divergence across the four faces.

    `adr_omits` is a parameter so the self-test can give the ADR face content the
    ledger face lacks. With the two synthetic faces byte-identical, both the
    direction asymmetry and the face wiring were unguarded.
    """
    ratio_pins = fixture_ratio_pins(fixture)
    wash_pins = fixture_wash_pins(fixture)

    ledger_31 = section(ledger, LEDGER_31, NEXT_SUBSECTION, "ledger §3.1")
    ledger_32 = section(ledger, LEDGER_32, NEXT_SUBSECTION, "ledger §3.2")
    adr_washes = section(adr, ADR_WASHES, NEXT_SECTION, "ADR-028 § Amendment 2026-08-15")
    adr_span = section(adr, ADR_SPAN, NEXT_SECTION, "ADR-028 § Amendment 2026-08-13 (#1427)")
    ds_8 = section(design_system, DESIGN_SYSTEM_8, NEXT_SECTION, "design-system §8")

    problems = compare_ratios(
        ledger_opaque_rows(ledger_31, "ledger §3.1"), ratio_pins, "ledger §3.1"
    )
    problems += compare_wash(
        wash_table_rows(ledger_32, "ledger §3.2"), wash_pins, "ledger §3.2", omits=set()
    )
    problems += compare_wash(
        wash_table_rows(adr_washes, "ADR-028 § Amendment 2026-08-15"),
        wash_pins,
        "ADR-028 § Amendment 2026-08-15",
        omits=adr_omits,
    )
    for lines, where in (
        (ledger_31, "ledger §3.1 span"),
        (ds_8, "design-system §8 span"),
        (adr_span, "ADR-028 § Amendment 2026-08-13 span"),
    ):
        problems += compare_span(span_in(lines, where), ratio_pins, where)

    # §5's per-site column, checked only for membership — see `compare_membership`
    # for why the direction is weaker here than on the other faces.
    pool = set(ratio_pins.values())
    for light, dark in wash_pins.values():
        pool |= {light[0], light[1], dark[0], dark[1]}
    ledger_5 = section(ledger, LEDGER_5, NEXT_SECTION, "ledger §5")
    problems += compare_membership(
        ledger_site_ratios(ledger_5, "ledger §5"), pool, "ledger §5"
    )
    return problems


# --- the residue report (#1496) ---------------------------------------------
#
# `--residue` enumerates the figures this gate does NOT reach. It is code rather
# than prose because four hand-written versions of that list were wrong, each
# differently. Report-only: it never fails, is not wired into the gate, and is
# the one thing here that shells out to git.

# An ALLOWLIST — every other suffix, and every extensionless tracked file, is
# skipped. The distinct skipped suffixes are printed for that reason, so a new
# `.astro` or `.css` copy cannot hide behind a bare count.
RESIDUE_SUFFIXES = frozenset(
    {".md", ".swift", ".py", ".sh", ".yml", ".yaml", ".html", ".kt", ".txt"}
)


def residue_rows(
    pool: set[str], read_index: set[tuple[str, int]], files: list[tuple[str, str]]
) -> tuple[list[tuple[str, int, list[str]]], list[tuple[str, int, list[str]]]]:
    """`(prose, executed)` hits outside `read_index`, one row per line.

    A non-comment line in a `.swift` file is an **executed assertion** — a guard
    rather than a copy that can rot — so it is separated, not counted or dropped.
    """
    prose: list[tuple[str, int, list[str]]] = []
    executed: list[tuple[str, int, list[str]]] = []
    for path, text in files:
        for i, line in enumerate(text.splitlines(), start=1):
            if (path, i) in read_index:
                continue
            found = sorted({v for v in pool if v in line}, key=float)
            if not found:
                continue
            is_code = path.endswith(".swift") and not line.lstrip().startswith("//")
            (executed if is_code else prose).append((path, i, found))
    return prose, executed


def residue() -> int:
    try:
        return _residue()
    except AnchorError as exc:
        print(f"measurement-transcript residue: {exc}", file=sys.stderr)
        print(
            "The report cannot judge with a broken anchor. Fix it (or this mode) — "
            "the gate itself is unaffected; run --check for its verdict.",
            file=sys.stderr,
        )
        return 1


def gate_read_index(
    faces: list[tuple[str, str, re.Pattern[str], re.Pattern[str]]],
    fixture_path: str,
    fixture: str,
) -> set[tuple[str, int]]:
    """`(path, 1-based line)` for everything the gate actually compares.

    Factored out of `_residue` so the **wiring** is armed, not merely the helper
    it calls: dropping the whole-block subtraction below leaves a
    `logical_blocks_with_offsets` unit arm green.
    """
    index: set[tuple[str, int]] = set()
    for path, text, start, nxt in faces:
        lines = text.splitlines()
        span = _section_lines(text, start, nxt, path)
        for i in span:
            if lines[i].strip().startswith("|"):
                index.add((path, i + 1))
        # The fixture-naming block, WHOLE: `span_in` reads the joined block, so
        # subtracting only the line carrying the name leaves the line carrying
        # the figure looking unguarded whenever the sentence is hard-wrapped.
        for block, offsets in logical_blocks_with_offsets(lines[span.start : span.stop]):
            if FIXTURE_NAME in block:
                for offset in offsets:
                    index.add((path, span.start + offset + 1))
    # Line-granular for the fixture: nothing in the pin arrays is wrapped today.
    # If swift-format ever wraps a `WashRowPin(`, its continuation lines surface
    # under "executed assertions" — mislabelled but harmless.
    for i, line in enumerate(fixture.splitlines(), start=1):
        if SWIFT_RATIO_PIN.search(line) or "WashRowPin(site:" in line:
            index.add((fixture_path, i))
    return index


def _residue() -> int:
    fixture = _read(FIXTURE_PATH)
    pool = set(fixture_ratio_pins(fixture).values())
    for light, dark in fixture_wash_pins(fixture).values():
        pool |= {light[0], light[1], dark[0], dark[1]}
    brackets = _decl_block(fixture, BRACKET_DECL, str(FIXTURE_PATH))
    pool |= {canonical(m.group(2)) for m in SWIFT_RATIO_PIN.finditer(brackets)}

    ledger, adr, design_system = _read(LEDGER_PATH), _read(ADR_PATH), _read(DESIGN_SYSTEM_PATH)
    read_index = gate_read_index(
        [
            (str(LEDGER_PATH), ledger, LEDGER_31, NEXT_SUBSECTION),
            (str(LEDGER_PATH), ledger, LEDGER_32, NEXT_SUBSECTION),
            (str(LEDGER_PATH), ledger, LEDGER_5, NEXT_SECTION),
            (str(ADR_PATH), adr, ADR_WASHES, NEXT_SECTION),
            (str(ADR_PATH), adr, ADR_SPAN, NEXT_SECTION),
            (str(DESIGN_SYSTEM_PATH), design_system, DESIGN_SYSTEM_8, NEXT_SECTION),
        ],
        str(FIXTURE_PATH),
        fixture,
    )

    try:
        listed = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files", "-z"],
            capture_output=True, check=True,
        ).stdout.decode("utf-8").split("\0")
    except FileNotFoundError as exc:
        raise AnchorError("residue: `git` is not on PATH — this mode enumerates tracked files.") from exc
    except subprocess.CalledProcessError as exc:
        raise AnchorError(
            "residue: `git ls-files` failed — not a repository, or the index is unreadable. "
            f"git said: {exc.stderr.decode('utf-8', 'replace').strip()}"
        ) from exc
    files: list[tuple[str, str]] = []
    skipped: dict[str, int] = {}
    for name in listed:
        if not name:
            continue
        suffix = Path(name).suffix or "(no suffix)"
        if Path(name).suffix not in RESIDUE_SUFFIXES:
            skipped[suffix] = skipped.get(suffix, 0) + 1
            continue
        try:
            files.append((name, (REPO_ROOT / name).read_text(encoding="utf-8")))
        except (OSError, UnicodeDecodeError):
            skipped[suffix] = skipped.get(suffix, 0) + 1

    prose, executed = residue_rows(pool, read_index, files)
    by_file: dict[str, list[tuple[int, list[str]]]] = {}
    for path, line, values in prose:
        by_file.setdefault(path, []).append((line, values))

    total_skipped = sum(skipped.values())
    print(
        f"measurement-transcript residue: {len(pool)} distinct pinned values | "
        f"{len(prose)} prose lines across {len(by_file)} files | "
        f"{len(executed)} executed assertion lines | "
        f"{len(files)} tracked files scanned, {total_skipped} skipped"
    )
    # The matching contract, stated because the report's value is being
    # authoritative: an EXACT literal match against the pinned three-decimal
    # form. A pinned value restated at a shorter precision is NOT seen (mostly
    # SwiftUI spacing constants, when measured). No example is spelled out — this
    # module must stay free of pinned literals its own report would then list.
    print(
        "  matched: exact literal, three decimals. Skipped suffixes: "
        + ", ".join(f"{suffix}×{n}" for suffix, n in sorted(skipped.items()))
    )
    for path in sorted(by_file, key=lambda p: (-len(by_file[p]), p)):
        rows = sorted(by_file[path])
        distinct = sorted({v for _, values in rows for v in values}, key=float)
        print(f"\n{path}: {len(rows)} prose lines, {len(distinct)} distinct")
        for line, values in rows:
            print(f"  :{line}  {' '.join(values)}")
    if executed:
        print("\nExecuted assertions (guards, not residue):")
        for path, line, values in sorted(executed):
            print(f"  {path}:{line}  {' '.join(values)}")
    return 0


def check() -> int:
    try:
        problems = collect(
            _read(FIXTURE_PATH), _read(LEDGER_PATH), _read(ADR_PATH), _read(DESIGN_SYSTEM_PATH)
        )
    except AnchorError as exc:
        print(f"measurement-transcript gate: {exc}", file=sys.stderr)
        print(
            "Fix the anchor (or this checker) — the gate refuses to pass without judging.",
            file=sys.stderr,
        )
        return 1
    if problems:
        print(
            "measurement-transcript gate: the docs and the fixture state different "
            "figures.\n"
            f"The fixture is the source — it computes them; {FIXTURE_PATH} carries "
            "the pins, and `scripts/xcodebuild.sh test -only-testing "
            "PasturaTests/DesignTokensTests` prints any that moved.\n",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print("measurement-transcript gate: clean (4 faces mirrored, ledger §5 within the pin set)")
    return 0


# --- self-test fixtures -----------------------------------------------------
#
# Synthetic figures throughout: these fixtures are self-consistent, so real
# values here would add decoy hits to any value-shaped sweep of the tree.

SYNTH_FIXTURE = """\
extension DesignTokensTests {
  private static let opaqueGroundPins: [(name: String, ratio: Double)] = [
    ("alphaGround", 9.111),
    ("betaGround", 9.777)
  ]

  private static let washRowPins: [WashRowPin] = [
    WashRowPin(site: "AlphaSite", light: (8.100, 8.100), dark: (8.200, 8.200)),
    WashRowPin(site: "BetaSite", light: (8.300, 8.400), dark: (8.500, 8.600))
  ]

  @Test func decoy() {
    let outside = ("gammaGround", 9.999)
    _ = WashRowPin(site: "GammaSite", light: (1.000, 1.000), dark: (1.000, 1.000))
    _ = outside
  }
}
"""

SYNTH_SPAN_BLOCK = (
    f"Pinned by `{FIXTURE_NAME}`; §8 carries the same span.\n"
    "`muted` runs **9.111–9.777** across them.\n"
)

# A sibling bullet carrying its own range and NOT naming the fixture. Live
# control for the span anchor in the design-system arm: loosen the block anchor
# and this range is picked up, so the arm reddens. Three load-bearing
# properties, none of them incidental:
#
# - **Synthetic figures**, or the decoy becomes live shipped `design-system.md`
#   text, refuting the synthetic-throughout rule above.
# - **Wave dash, not en dash** — the real §8 spells its span with `〜`, so the
#   decoy's discriminating power depends on `RANGE` admitting it. The
#   `range: a wave-dash span is read` arm is what reddens if `RANGE` narrows.
# - **No blank line before it.** The real §8's bullets are adjacent, so only the
#   `LIST_ITEM` flush separates them; with a blank line here, deleting that
#   flush from `logical_blocks` leaves the suite green.
SYNTH_DECOY_RANGE = "- the ink family ran 7.413〜7.773 in dark before #9999\n"

SYNTH_OPAQUE_TABLE = (
    "| Light ground | ratio | Dark ground | ratio |\n"
    "|---|---|---|---|\n"
    "| `alphaGround` | 9.111 ← the calibration point | `betaGround` | **9.777** |\n"
)

SYNTH_WASH_HEADER_ONLY = "| Site | Wash over ground | light | dark |\n|---|---|---|---|\n"

SYNTH_WASH_TABLE = (
    SYNTH_WASH_HEADER_ONLY
    + "| `AlphaSite.pill(.pending)` | `x@0.14` over a ground | 8.100 | 8.200 |\n"
    "| `BetaSite` chip | `y@0.45` over every ground | 8.300–8.400 | 8.500–8.600 |\n"
)


# §5's site tables. Two of them, because a single-table fixture cannot witness
# the walk continuing past the first. The `Tally` table is exempt *structurally*
# — it carries no three-digit ratio — and its "WCAG 1.4.11" is why the exemption
# tests three-digit precision rather than `DECIMAL`, which that string satisfies.
SYNTH_LEDGER_5_HEADER = (
    "| Site (file · symbol) | Ground | light/dark | Verdict | B |\n|---|---|---|---|---|\n"
)

SYNTH_LEDGER_5_TABLES = (
    "### Components\n\n"
    + SYNTH_LEDGER_5_HEADER
    + "| `AlphaView` · caption | `alphaGround` | 9.111 / 9.777 | S | — |\n"
    "| `AlphaView` · comment | — | — | C | — |\n\n"
    "### Results\n\n"
    + SYNTH_LEDGER_5_HEADER
    + "| `BetaView` · pill | `x@0.14` | 8.100 / 8.200 | **M (A4)** | B2 |\n"
    "| `BetaView` · timestamp | same | same | S | — |\n\n"
    "### Tally\n\n"
    "| | count |\n|---|---|\n"
    "| — non-text (WCAG 1.4.11, out of §8's scope) | 16 |\n"
)


def synth_ledger(
    opaque: str = SYNTH_OPAQUE_TABLE,
    wash: str = SYNTH_WASH_TABLE,
    ledger_5: str = SYNTH_LEDGER_5_TABLES,
) -> str:
    return (
        "## 3. Grounds\n\n"
        "### 3.1 The twelve opaque grounds\n\n" + SYNTH_SPAN_BLOCK + "\n" + opaque + "\n"
        # The arm for `NEXT_SUBSECTION`: re-narrow it to `^#{2,3} ` and §3.1's
        # slice runs on into this block, which names the fixture and states a
        # different span, so `span_in` reddens.
        "#### A later note\n\n"
        f"`{FIXTURE_NAME}` once ran 5.111–5.777 here.\n\n"
        "### 3.2 Composited grounds\n\n" + wash + "\n"
        "### 3.3 Grounds that are not computable\n\nprose\n\n"
        "## 4. Recorded refusal\n\nprose\n\n"
        "## 5. The ledger\n\n" + ledger_5 + "\n"
        "## 6. Decisions\n\nprose\n"
    )


# The ADR face must NOT be a byte-identical copy of the ledger's, or a
# face-identity arm cannot exist at all: with the two identical, flipping the ADR
# comparison to the bijection direction and repointing it at the ledger's own
# section both stayed green. Omitting `BetaSite` exercises the real asymmetry.
SYNTH_ADR_WASH_TABLE = (
    SYNTH_WASH_HEADER_ONLY
    + "| `AlphaSite` pill | `x@0.14` over a ground | 8.100 | 8.200 |\n"
)
SYNTH_ADR_OMITS = {"BetaSite"}


def synth_adr(wash: str = SYNTH_ADR_WASH_TABLE, span: str = SYNTH_SPAN_BLOCK) -> str:
    return (
        "## Amendment 2026-08-13 — the quietude tier is ground-relative (#1427)\n\n"
        + span
        + "\n"
        "## Amendment 2026-08-14 — something else (#1455)\n\nprose\n\n"
        "## Amendment 2026-08-15 — the second unmeasured ground (#1448)\n\n"
        # The arm for `NEXT_SECTION`: swap the ADR to `NEXT_SUBSECTION` and the
        # slice ends at this `###`, before the table. The real ADR has this shape.
        "### The washes are a second unmeasured ground\n\n" + wash + "\n"
        "## Related\n\nprose\n"
    )


def synth_design_system(span: str = SYNTH_SPAN_BLOCK) -> str:
    # No blank line before the decoy — see `SYNTH_DECOY_RANGE`.
    return (
        "## 7. Copywriting\n- unrelated\n\n"
        "## 8. Accessibility\n\n" + span + SYNTH_DECOY_RANGE + "\n"
        "## 9. Rollout\n- unrelated\n"
    )


def self_test() -> int:
    """Positive and negative controls.

    Every arm asserts an **exact** value rather than merely flagged/clean, so a
    decoy leaking into an extractor is caught by that extractor's own arm and not
    only by whichever comparison happens to notice.
    """
    failures = 0
    checked = 0

    def fail(name: str, detail: str) -> None:
        nonlocal failures
        print(f"self-test FAILED: {name} — {detail}", file=sys.stderr)
        failures += 1

    def expect(name: str, thunk, want: object) -> None:
        """`thunk`, not a value: an unexpected `AnchorError` raised while
        building the argument would otherwise abort every remaining arm with a
        traceback and no tally.
        """
        nonlocal checked
        checked += 1
        try:
            got = thunk()
        except AnchorError as exc:
            fail(name, f"unexpected AnchorError: {exc}")
            return
        if got != want:
            fail(name, f"expected {want!r}, got {got!r}")

    def expect_raises(name: str, because: str, thunk) -> None:
        """`because` names WHICH anchor must fire, not merely that one did.

        Without it an arm passes off any neighbouring anchor and a mutation that
        missed its target reads as coverage — as the emptied-array arm below did,
        firing `_decl_block`'s bracket anchor instead of the empty-set one.
        """
        nonlocal checked
        checked += 1
        try:
            got = thunk()
        except AnchorError as exc:
            if because not in str(exc):
                fail(name, f"raised the wrong anchor: wanted {because!r}, got {str(exc)!r}")
            return
        fail(name, f"expected AnchorError, got {got!r}")

    ledger, adr, design_system = synth_ledger(), synth_adr(), synth_design_system()

    def ledger_section(head: str, text: str = "") -> list[str]:
        return section(
            text or ledger, re.compile(head), NEXT_SUBSECTION, "ledger"
        )

    # --- extraction: the fixture -------------------------------------------

    expect(
        "fixture: ratio pins, and a decoy tuple outside the declaration stays out",
        lambda: fixture_ratio_pins(SYNTH_FIXTURE),
        {"alphaGround": "9.111", "betaGround": "9.777"},
    )
    expect(
        "fixture: wash pins, and a decoy WashRowPin outside the declaration stays out",
        lambda: fixture_wash_pins(SYNTH_FIXTURE),
        {
            "AlphaSite": (("8.100", "8.100"), ("8.200", "8.200")),
            "BetaSite": (("8.300", "8.400"), ("8.500", "8.600")),
        },
    )
    expect(
        "fixture: a swift-format-wrapped WashRowPin is still read",
        lambda: fixture_wash_pins(
                SYNTH_FIXTURE.replace(
                    '    WashRowPin(site: "BetaSite", light: (8.300, 8.400), dark: (8.500, 8.600))',
                    "    WashRowPin(\n"
                    '      site: "BetaSite", light: (8.300, 8.400),\n'
                    "      dark: (8.500, 8.600))",
                )
            )["BetaSite"],
        (("8.300", "8.400"), ("8.500", "8.600")),
    )

    # --- extraction: the docs ----------------------------------------------

    expect(
        "ledger §3.1: annotations and bold markers are stripped off the ratios",
        lambda: ledger_opaque_rows(ledger_section(r"^### 3\.1"), "ledger §3.1"),
        {"alphaGround": "9.111", "betaGround": "9.777"},
    )
    expect(
        "ledger §3.1: the row-wise light↔dark pairing, which the flat pins do not carry",
        lambda: ledger_opaque_pairs(ledger_section(r"^### 3\.1"), "ledger §3.1"),
        {"alphaGround": "betaGround"},
    )
    expect(
        "ledger §3.2: the ground token of each wash row, keyed to the same site key",
        lambda: wash_row_grounds(ledger_section(r"^### 3\.2"), "ledger §3.2"),
        {"x@0.14": "AlphaSite", "y@0.45": "BetaSite"},
    )
    expect_raises(
        "ledger §3.2: a wash row's ground cell lost its backticks",
        "names no `wash` ground",
        lambda: wash_row_grounds(
            ledger_section(
                r"^### 3\.2",
                ledger.replace("| `x@0.14` over a ground |", "| over a ground |"),
            ),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger §3.2: two wash rows on the same ground would collapse the §5 lookup",
        "share a ground token",
        lambda: wash_row_grounds(
            ledger_section(
                r"^### 3\.2",
                ledger.replace("| `y@0.45` over every ground |", "| `x@0.14` over every ground |"),
            ),
            "ledger §3.2",
        ),
    )
    expect(
        "ledger §3.2: a point row and a range row, keyed by the leading identifier",
        lambda: wash_table_rows(ledger_section(r"^### 3\.2"), "ledger §3.2"),
        {
            "AlphaSite": (("8.100", "8.100"), ("8.200", "8.200")),
            "BetaSite": (("8.300", "8.400"), ("8.500", "8.600")),
        },
    )
    expect(
        "span: read out of the block naming the fixture, not searched for by value",
        lambda: span_in(ledger_section(r"^### 3\.1"), "ledger §3.1 span"),
        ("9.111", "9.777"),
    )
    expect(
        "span: a sibling bullet's own range is not the fixture's span",
        lambda: span_in(
                section(design_system, re.compile(r"^## 8\."), re.compile(r"^## "), "ds"),
                "design-system §8 span",
            ),
        ("9.111", "9.777"),
    )

    # --- anchors ------------------------------------------------------------
    #
    # Each would otherwise collapse to an empty set and compare "equal" against
    # the other side — a green gate that judged nothing.

    expect_raises(
        "fixture: the ratio-pin declaration was renamed",
        "no 'private static let opaqueGroundPins' declaration",
        lambda: fixture_ratio_pins(SYNTH_FIXTURE.replace("opaqueGroundPins", "groundPins")),
    )
    expect_raises(
        "fixture: the ratio-pin array was emptied",
        'yielded no `("name", ratio)` rows',
        # Replaced by a comment rather than deleted: deleting the rows also
        # deletes the closing bracket's indentation, and the arm then reddens off
        # `_decl_block`'s anchor instead of the empty-set one.
        lambda: fixture_ratio_pins(
            re.sub(
                r'    \("alphaGround".*\n    \("betaGround", 9\.777\)\n',
                "    // every ground was removed\n",
                SYNTH_FIXTURE,
            )
        ),
    )
    expect_raises(
        "fixture: the wash-pin declaration was renamed",
        "no 'private static let washRowPins' declaration",
        lambda: fixture_wash_pins(SYNTH_FIXTURE.replace("washRowPins", "washPins")),
    )
    expect_raises(
        "fixture: the wash-pin row shape changed",
        'yielded no `WashRowPin(...)` rows',
        lambda: fixture_wash_pins(SYNTH_FIXTURE.replace("WashRowPin(site:", "WashRow(site:")),
    )
    expect_raises(
        "ledger: §3.1 was renumbered away",
        'the section heading is gone',
        lambda: ledger_section(r"^### 3\.1", ledger.replace("### 3.1", "### 3.9")),
    )
    expect_raises(
        "ledger: §3.1's table header changed",
        'no table whose header row matches',
        lambda: ledger_opaque_rows(
            ledger_section(r"^### 3\.1", ledger.replace("| Light ground |", "| Ground |")),
            "ledger §3.1",
        ),
    )
    expect_raises(
        "ledger: §3.2's wash table lost its light/dark columns",
        'no table whose header row matches',
        lambda: wash_table_rows(
            ledger_section(r"^### 3\.2", ledger.replace("| light | dark |", "| ratios |")),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger: the wash table has a header but no rows",
        'the table has a header but no body rows',
        lambda: wash_table_rows(
            ledger_section(r"^### 3\.2", synth_ledger(wash=SYNTH_WASH_HEADER_ONLY)),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ADR: the 2026-08-15 amendment heading was reworded away",
        'the section heading is gone',
        lambda: section(
            adr.replace("## Amendment 2026-08-15", "## Amendment 2026-08-16"),
            re.compile(r"^## Amendment 2026-08-15\b"),
            re.compile(r"^## "),
            "ADR",
        ),
    )
    expect_raises(
        "span: the anchored block no longer names the fixture",
        'no paragraph or bullet in this section names',
        lambda: span_in(
            ledger_section(
                r"^### 3\.1", ledger.replace(FIXTURE_NAME, "SomeOtherTests+Renamed")
            ),
            "ledger §3.1 span",
        ),
    )
    expect_raises(
        "span: the anchored block states no span at all",
        'states no `low–high` span',
        lambda: span_in(
            ledger_section(r"^### 3\.1", ledger.replace("**9.111–9.777**", "a narrow band")),
            "ledger §3.1 span",
        ),
    )
    expect_raises(
        "fixture: the declaration's closing bracket moved off its indentation",
        "could not find the closing ']'",
        lambda: fixture_ratio_pins(
            SYNTH_FIXTURE.replace('    ("betaGround", 9.777)\n  ]', '    ("betaGround", 9.777)\n]')
        ),
    )
    expect_raises(
        "ledger §3.1: a row lost a column",
        'a §3.1 row has',
        lambda: ledger_opaque_rows(
            ledger_section(
                r"^### 3\.1",
                ledger.replace(" | `betaGround` | **9.777** |", " |"),
            ),
            "ledger §3.1",
        ),
    )
    expect_raises(
        "ledger §3.1: a ground cell lost its backticks",
        'a §3.1 row is not `name` + ratio',
        lambda: ledger_opaque_rows(
            ledger_section(r"^### 3\.1", ledger.replace("| `alphaGround` |", "| alphaGround |")),
            "ledger §3.1",
        ),
    )
    expect_raises(
        "ledger §3.2: a wash row lost a column",
        'a wash row has',
        lambda: wash_table_rows(
            ledger_section(r"^### 3\.2", ledger.replace(" | 8.100 | 8.200 |", " |")),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger §3.2: a Site cell names no `site`",
        'Site cell names no `site`',
        lambda: wash_table_rows(
            ledger_section(
                r"^### 3\.2", ledger.replace("| `AlphaSite.pill(.pending)` |", "| AlphaSite |")
            ),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger §3.2: a Site token is not identifier-shaped",
        'Site token is not identifier-shaped',
        lambda: wash_table_rows(
            ledger_section(
                r"^### 3\.2", ledger.replace("| `AlphaSite.pill(.pending)` |", "| `.pending` |")
            ),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger §3.2: a value cell carries prose instead of a figure",
        'a wash cell carries no figure',
        lambda: wash_table_rows(
            ledger_section(r"^### 3\.2", ledger.replace("| 8.100 | 8.200 |", "| n/a | 8.200 |")),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "span: the anchored block states two different spans",
        'states more than one span',
        lambda: span_in(
            ledger_section(
                r"^### 3\.1",
                ledger.replace(
                    "runs **9.111–9.777** across them.",
                    "runs **9.111–9.777** across them, or 9.111–9.500 by the old count.",
                ),
            ),
            "ledger §3.1 span",
        ),
    )
    expect_raises(
        "read: a missing input raises rather than escaping as OSError",
        'cannot read it',
        lambda: _read(Path("docs/design/no-such-file-for-the-self-test.md")),
    )

    # --- comparison ---------------------------------------------------------

    ratio_pins = fixture_ratio_pins(SYNTH_FIXTURE)
    wash_pins = fixture_wash_pins(SYNTH_FIXTURE)

    expect(
        "compare: the tree agrees with itself",
        lambda: collect(SYNTH_FIXTURE, ledger, adr, design_system, SYNTH_ADR_OMITS),
        [],
    )
    expect(
        "compare: a moved opaque ratio",
        lambda: collect(
            SYNTH_FIXTURE,
            ledger.replace("| 9.111 ←", "| 9.112 ←"),
            adr,
            design_system,
            SYNTH_ADR_OMITS,
        ),
        ["ledger §3.1: `alphaGround` reads 9.112, the fixture computes 9.111."],
    )
    expect(
        "compare: a moved wash bound, light side",
        lambda: compare_wash(
            {"BetaSite": (("8.300", "8.999"), ("8.500", "8.600"))},
            wash_pins,
            "face",
            omits={"AlphaSite"},
        ),
        ["face: `BetaSite` light reads 8.300–8.999, the fixture computes 8.300–8.400."],
    )
    # The dark tuple's wiring was covered only indirectly, by the arms that agree.
    expect(
        "compare: a moved wash bound, dark side",
        lambda: compare_wash(
            {"BetaSite": (("8.300", "8.400"), ("8.500", "8.999"))},
            wash_pins,
            "face",
            omits={"AlphaSite"},
        ),
        ["face: `BetaSite` dark reads 8.500–8.999, the fixture computes 8.500–8.600."],
    )
    expect(
        "compare: a doc row with no pin is flagged in both directions",
        lambda: compare_ratios({"alphaGround": "9.111", "deltaGround": "1.000"}, ratio_pins, "face"),
        [
            "face: `deltaGround` is transcribed but is not a pin — drop it or pin it.",
            "face: `betaGround` is pinned but is not transcribed — add the row.",
        ],
    )
    expect(
        "compare: a NAMED omission is not flagged, but an unknown row still is",
        lambda: compare_wash(
            {"GammaSite": (("1.000", "1.000"), ("1.000", "1.000"))},
            wash_pins,
            "face",
            omits={"AlphaSite", "BetaSite"},
        ),
        ["face: `GammaSite` is transcribed but is not a pin — drop it or pin it."],
    )
    expect(
        "compare: an UNNAMED omission is flagged — the face cannot silently shrink",
        lambda: compare_wash({"AlphaSite": wash_pins["AlphaSite"]}, wash_pins, "face", omits=set()),
        ["face: `BetaSite` is pinned but is not transcribed — add the row."],
    )
    # The other direction: a face that GAINS a row this checker still records as
    # deliberately absent must redden, or `HighlightShareCard` could be added to
    # ADR-028 and go unchecked.
    expect(
        "compare: a named omission that the face now carries is flagged",
        lambda: compare_wash(wash_pins, wash_pins, "face", omits={"BetaSite"}),
        [
            "face: `BetaSite` is recorded here as deliberately omitted, but the face "
            "now carries it — drop it from this checker's omission set."
        ],
    )
    expect(
        "compare: the span is the min and max of the pins, not a fourth measurement",
        lambda: compare_span(("9.111", "9.500"), ratio_pins, "face"),
        ["face: the span reads 9.111–9.500, but the pinned grounds run 9.111–9.777."],
    )
    expect(
        "compare: a span stale in one face only is still caught",
        lambda: collect(
            SYNTH_FIXTURE,
            ledger,
            adr,
            design_system.replace("9.777", "9.778"),
            SYNTH_ADR_OMITS,
        ),
        [
            "design-system §8 span: the span reads 9.111–9.778, but the pinned "
            "grounds run 9.111–9.777."
        ],
    )
    # Face identity: with the two synthetic faces byte-identical, repointing the
    # ADR comparison at the ledger's own section left the suite green. These arms
    # pin the label on a mutation only the ADR text carries.
    expect(
        "compare: a figure stale in the ADR wash table only is labelled as the ADR's",
        lambda: collect(
            SYNTH_FIXTURE,
            ledger,
            adr.replace("| 8.100 | 8.200 |", "| 8.101 | 8.200 |"),
            design_system,
            SYNTH_ADR_OMITS,
        ),
        [
            "ADR-028 § Amendment 2026-08-15: `AlphaSite` light reads 8.101–8.101, "
            "the fixture computes 8.100–8.100."
        ],
    )
    expect(
        "compare: a span stale in the ADR only is labelled as the ADR's",
        lambda: collect(
            SYNTH_FIXTURE,
            ledger,
            synth_adr(span=SYNTH_SPAN_BLOCK.replace("9.777", "9.778")),
            design_system,
            SYNTH_ADR_OMITS,
        ),
        [
            "ADR-028 § Amendment 2026-08-13 span: the span reads 9.111–9.778, but "
            "the pinned grounds run 9.111–9.777."
        ],
    )

    # --- properties the arms above depend on ---------------------------------

    # `SYNTH_DECOY_RANGE` is wave-dash separated, like the real §8 span. Narrow
    # `RANGE` to `[–—]` and the decoy silently stops being a control.
    expect(
        "range: a wave-dash span is read",
        lambda: span_in(
            ledger_section(
                r"^### 3\.1", ledger.replace("**9.111–9.777**", "**9.111〜9.777**")
            ),
            "ledger §3.1 span",
        ),
        ("9.111", "9.777"),
    )
    # `canonical` exists so `1.2` and `1.200` agree; every other fixture writes
    # three digits on both sides, so without this arm it is only ever identity.
    expect(
        "canonical: a doc cell at fewer digits still matches a three-digit pin",
        lambda: ledger_opaque_rows(
            ledger_section(r"^### 3\.1", ledger.replace("| 9.111 ←", "| 9.11 ←")),
            "ledger §3.1",
        ),
        {"alphaGround": "9.110", "betaGround": "9.777"},
    )
    # A pin written as an integer literal is legal Swift for a `Double`.
    # Unmatched, the row vanishes from the extracted dict and the gate blames the
    # DOC — the inverted diagnosis again.
    expect(
        "fixture: an integer pin literal is read, not dropped",
        lambda: fixture_ratio_pins(SYNTH_FIXTURE.replace('("betaGround", 9.777)', '("betaGround", 9)')),
        {"alphaGround": "9.111", "betaGround": "9.000"},
    )

    # --- cardinality guards --------------------------------------------------
    #
    # Both keys are lossy, so a repeat OVERWRITES and the earlier row's figures
    # are never compared — which the set-based bijections downstream cannot see.

    expect_raises(
        "ledger §3.1: a repeated ground name would silently overwrite",
        "a ground name is repeated",
        lambda: ledger_opaque_rows(
            ledger_section(
                r"^### 3\.1",
                ledger.replace(
                    "| `alphaGround` | 9.111 ← the calibration point | `betaGround` | **9.777** |\n",
                    "| `alphaGround` | 1.111 | `betaGround` | 2.222 |\n"
                    "| `alphaGround` | 9.111 ← the calibration point | `betaGround` | **9.777** |\n",
                ),
            ),
            "ledger §3.1",
        ),
    )
    expect_raises(
        "ledger §3.2: two rows on the same view collapse onto one site key",
        "collapsed onto",
        lambda: wash_table_rows(
            ledger_section(
                r"^### 3\.2",
                ledger.replace(
                    "| `BetaSite` chip |",
                    "| `AlphaSite.completed` | `z@0.2` over a ground | 1.000 | 1.000 |\n"
                    "| `BetaSite` chip |",
                ),
            ),
            "ledger §3.2",
        ),
    )
    expect_raises(
        "ledger §3.1: an inserted column shifts the ratio cells",
        "cells, expected 4",
        lambda: ledger_opaque_rows(
            ledger_section(
                r"^### 3\.1",
                ledger.replace("| `alphaGround` | 9.111 ←", "| note | `alphaGround` | 9.111 ←"),
            ),
            "ledger §3.1",
        ),
    )
    expect_raises(
        "ledger §3.2: an inserted column shifts the light/dark cells",
        "cells, expected 4",
        lambda: wash_table_rows(
            ledger_section(
                r"^### 3\.2",
                ledger.replace("| `AlphaSite.pill(.pending)` |", "| note | `AlphaSite.pill(.pending)` |"),
            ),
            "ledger §3.2",
        ),
    )

    # --- ledger §5 membership (#1488) -----------------------------------
    def ledger_5_of(text: str) -> list[str]:
        return section(text, LEDGER_5, NEXT_SECTION, "ledger §5")

    synth_pool = {"9.111", "9.777", "8.100", "8.200", "8.300", "8.400", "8.500", "8.600"}

    # Exact pairs, not a count: the second table's rows are what prove the walk
    # does not stop at the first the way `table_rows` does.
    expect(
        "ledger §5: every site table's ratio column is read, across sub-tables",
        lambda: ledger_site_ratios(ledger_5_of(ledger), "ledger §5"),
        [
            ("`AlphaView` · caption", "9.111"),
            ("`AlphaView` · caption", "9.777"),
            ("`BetaView` · pill", "8.100"),
            ("`BetaView` · pill", "8.200"),
        ],
    )
    expect(
        "ledger §5: a clean ledger reports nothing",
        lambda: compare_membership(
            ledger_site_ratios(ledger_5_of(ledger), "ledger §5"), synth_pool, "ledger §5"
        ),
        [],
    )
    def unpinned_report() -> tuple[int, bool, bool, bool]:
        """Count, plus which row and value the message names — a bare count
        would pass off any message.
        """
        problems = compare_membership(
            ledger_site_ratios(
                ledger_5_of(
                    synth_ledger(
                        ledger_5=SYNTH_LEDGER_5_TABLES.replace(
                            "| 8.100 / 8.200 |", "| 7.777 / 8.200 |"
                        )
                    )
                ),
                "ledger §5",
            ),
            synth_pool,
            "ledger §5",
        )
        joined = " ".join(problems)
        return (
            len(problems),
            "`BetaView` · pill" in joined,
            "7.777" in joined,
            "`AlphaView`" in joined,
        )

    expect(
        "ledger §5: a figure matching no pin is reported, naming its row",
        unpinned_report,
        (1, True, True, False),
    )
    expect_raises(
        "ledger §5: a ratio table whose header drifted would go unchecked",
        "header row no longer matches",
        lambda: ledger_site_ratios(
            ledger_5_of(synth_ledger(ledger_5=SYNTH_LEDGER_5_TABLES.replace(
                "| Site (file · symbol) | Ground | light/dark | Verdict | B |\n|---|---|---|---|---|\n"
                "| `BetaView` · pill |",
                "| Where | Ground | light/dark | Verdict | B |\n|---|---|---|---|---|\n"
                "| `BetaView` · pill |",
            ))),
            "ledger §5",
        ),
    )
    # The exemption must come from carrying no ratio, not from the table's name.
    expect_raises(
        "ledger §5: the Tally-shaped table stops being exempt once it carries a ratio",
        "header row no longer matches",
        lambda: ledger_site_ratios(
            ledger_5_of(synth_ledger(ledger_5=SYNTH_LEDGER_5_TABLES.replace(
                "| — non-text (WCAG 1.4.11, out of §8's scope) | 16 |",
                "| — non-text (WCAG 1.4.11, out of §8's scope) | 9.111 |",
            ))),
            "ledger §5",
        ),
    )
    expect_raises(
        "ledger §5: an inserted column shifts the ratio cell",
        "cells, expected 5",
        lambda: ledger_site_ratios(
            ledger_5_of(synth_ledger(ledger_5=SYNTH_LEDGER_5_TABLES.replace(
                "| `AlphaView` · caption |", "| note | `AlphaView` · caption |"))),
            "ledger §5",
        ),
    )
    expect_raises(
        "ledger §5: emptied tables must not agree with the pins by carrying nothing",
        "no ratio cell yielded a decimal",
        lambda: ledger_site_ratios(
            ledger_5_of(synth_ledger(ledger_5=SYNTH_LEDGER_5_HEADER)), "ledger §5"
        ),
    )
    expect_raises(
        "ledger §5: the section heading was renumbered",
        "the section heading is gone",
        lambda: ledger_5_of(ledger.replace("## 5. The ledger", "## 5bis. The ledger")),
    )

    # --- residue classification (#1496) ---------------------------------
    #
    # `--residue` shells out to git and reads the whole tree, so only its
    # classification is unit-testable — and that is the half that was wrong.
    residue_files = [
        ("docs/x.md", "| a | 9.111 |\nprose 9.777 here\n"),
        ("Some/Fixture.swift", "    #expect(x == 9.111)\n    /// prose 9.777\n"),
    ]
    expect(
        "residue: a read line is subtracted, prose is kept, assertions are split out",
        lambda: residue_rows({"9.111", "9.777"}, {("docs/x.md", 1)}, residue_files),
        (
            [("docs/x.md", 2, ["9.777"]), ("Some/Fixture.swift", 2, ["9.777"])],
            [("Some/Fixture.swift", 1, ["9.111"])],
        ),
    )
    # Not a weaker restatement of the arm above: subtracting by
    # `line.startswith("|")` instead of by the read index leaves that one green
    # and only this red. It pins the subtraction to the index, not a line's shape.
    expect(
        "residue: without the read-index entry the table row is residue too",
        lambda: len(residue_rows({"9.111", "9.777"}, set(), residue_files)[0]),
        3,
    )
    # The offsets a wrapped block spans — the whole block, not just the line
    # carrying the fixture name.
    wrapped = [
        "Pinned by `Some+Fixture`; §8 carries",
        "the same span. It runs 9.111–9.777 across them.",
        "",
        "An unrelated paragraph naming nothing.",
    ]
    expect(
        "residue: a hard-wrapped block is subtracted whole, figure line included",
        lambda: [
            offsets for block, offsets in logical_blocks_with_offsets(wrapped)
            if "Some+Fixture" in block
        ],
        [[0, 1]],
    )
    # The WIRING, not just the helper: removing the whole-block loop in
    # `gate_read_index` leaves the two arms above green and only this one red.
    wrapped_face = (
        "### 3.1 The twelve opaque grounds\n\n"
        f"Pinned by `{FIXTURE_NAME}`; §8 carries\n"
        "the same span. `muted` runs **9.111–9.777** across them.\n\n"
        "| Light ground | ratio | Dark ground | ratio |\n"
        "|---|---|---|---|\n"
        "| `alphaGround` | 9.111 | `betaGround` | 9.777 |\n\n"
        "#### A later note\n\nprose\n"
    )
    expect(
        "residue: the read index subtracts a wrapped span block whole",
        lambda: sorted(
            line
            for path, line in gate_read_index(
                [("face.md", wrapped_face, LEDGER_31, NEXT_SUBSECTION)], "fix.swift", ""
            )
            if path == "face.md"
        ),
        [3, 4, 6, 7, 8],
    )
    expect(
        "residue: block offsets stay aligned with `logical_blocks`",
        lambda: [block for block, _ in logical_blocks_with_offsets(wrapped)],
        logical_blocks(wrapped),
    )

    # --- Trigger coverage (#1488) ---------------------------------------
    #
    # The only arms reading the REAL tree, deliberately: the invariant is this
    # checker's path constants and the live gate script agreeing, which no
    # synthetic pair can witness. The decoys keep the positive arm honest.
    real_trigger = gate_trigger(_read(GATE_PATH))
    expect(
        "trigger coverage: every path this checker reads also fires the gate",
        lambda: uncovered_inputs(real_trigger),
        [],
    )

    def trigger_without(needle: str) -> str:
        """The real trigger with the alternative naming `needle` removed."""
        alternatives = [alt for alt in real_trigger.split("|") if needle not in alt]
        assert len(alternatives) == len(real_trigger.split("|")) - 1, (
            f"decoy did not remove exactly one alternative for {needle!r}"
        )
        return "|".join(alternatives)

    expect(
        "trigger coverage: a dropped ledger alternative is reported, not absorbed",
        lambda: uncovered_inputs(trigger_without("muted-application-audit")),
        [str(LEDGER_PATH)],
    )
    expect(
        "trigger coverage: a dropped fixture alternative is reported too",
        lambda: uncovered_inputs(trigger_without("MutedTranscript")),
        [str(FIXTURE_PATH)],
    )
    # The circularity here — the checker reads the gate, so the gate must trigger
    # on itself — is the claim least likely to be re-derived later.
    expect(
        "trigger coverage: the gate's own alternative is covered, not assumed",
        lambda: uncovered_inputs(trigger_without("measurement-transcript-precommit-gate")),
        [str(GATE_PATH)],
    )
    expect_raises(
        "trigger coverage: the gate no longer assigns TRIGGER on its own line",
        "no `TRIGGER=",
        lambda: gate_trigger(_read(GATE_PATH).replace("TRIGGER=", "TRIGGER_RENAMED=")),
    )

    if failures:
        return 1
    print(f"measurement-transcript self-test: {checked}/{checked} passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--residue", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        rc = self_test()
        if rc or not (args.check or args.residue):
            return rc
    if args.check:
        rc = check()
        if rc or not args.residue:
            return rc
    if args.residue:
        return residue()
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
