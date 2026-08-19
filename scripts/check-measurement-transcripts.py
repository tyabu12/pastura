#!/usr/bin/env python3
r"""Guard: the contrast figures `docs/**` transcribes and the ones
`DesignTokensTests+MutedAsContent` pins are the **same numbers** (#1488).

Three doc faces copy figures the fixture computes, and before #1488 nothing
compared them:

- `muted-application-audit.md` §3.1 — the twelve opaque grounds, plus the
  derived span sentence.
- `muted-application-audit.md` §3.2 — the five wash rows.
- `ADR-028.md` § Amendment 2026-08-15 — a **four-row** copy of that same wash
  table, and § Amendment 2026-08-13's copy of the span.
- `design-system.md` §8 — a third copy of the span.

§3.2 already calls itself "a transcript rather than a second source". It was not
one: every `#expect` in the fixture is an inequality or an ordering, so no arm
named a figure at all and there was nothing to transcribe *from*. #1488 adds the
pins; this gate is what makes them reach the docs.

**Why not the mechanism #1488's issue body proposed.** That issue proposed a
tree-wide exact-match grep for high-precision literals. Measured, most of its
firings are structure the repo mandates — `ds/README.md` orders `ds/*.html` to
mirror `design-system.md`, and ADR-028 § "Where new amendment content goes"
orders measurements into an amendment — so the gate would fire forever on
correct text. Worse, it catches **none** of the three defects the issue itself
records from PR #1486 (a quantized script, a ground read off a token name, two
rows carrying no `muted` text): not one of those is a duplicate, and ADR-028
§ "A count mirror that a count-keyed sweep structurally cannot find" already
records that a value-keyed sweep hits only the copies that are still in sync.
This gate instead makes the docs' *self-declared* canonical source real.

**No colour arithmetic lives here.** `design-system.md` §8 warns that a
hand-rolled script quantizing channels to 0–255 diverges from the fixture, and
that warning is about exactly the script someone would write next. Everything
below is string and decimal comparison; the fixture stays the only thing that
composites a colour.

**What a green run does NOT certify.** That the doc rows describe the right
sites, that a site still paints the wash its arm composites, or that a ground
read off the view hierarchy is correct. §3.2 files its own corrections under
"beyond the arithmetic, all from reading the sites rather than the table", and a
pin would have caught none of them. Green means the numbers agree, no more.

It also reads only the **anchored tables and span blocks**, so a figure restated
anywhere else is unchecked. Enumerated rather than recalled (#1496 carries the
measurement): the ledger §5 per-site ratio column, prose restatements of a single
figure — including ADR-028's own decision-summary table row — the fixture's
doc-comment prose, and two other test files plus one production doc comment.
`ds/*.html` is **not** on that list: it carries three-decimal ratios, but of a
different population (ground-vs-ground contrast and per-channel pair gaps), none
of them a copy of these pins.

Anchors. Every one is asserted rather than allowed to degrade — a renumbered
heading, a renamed declaration, a table whose header row changed, an
**empty extracted set**, or an unreadable input each raises instead of
collapsing into an empty-vs-empty "equal" pass.

The span sentence is anchored **structurally, not by its value**: within the
section, the logical block that names `DesignTokensTests+MutedAsContent` is the
one that claims the fixture pins the twelve, and the span literal is read out of
it. Searching for `2.136` would find what it was told to find and prove nothing.

Directions differ by face, deliberately:

- §3.1 and §3.2 are **bijections** with the pins. One-way containment lets an
  unmatched row drop out of the comparison silently, which is the failure this
  file exists to remove.
- ADR-028's table is a **subset**: it carries four of the five rows (no
  `HighlightShareCard`) and words the `ReportSheet` ground differently. Every
  ADR row must match a pin; a pin with no ADR row is correct.

Trigger paths live in `scripts/measurement-transcript-precommit-gate.sh`, which
is what self-gates on them — one copy, so the two cannot drift.

Usage:
    python3 scripts/check-measurement-transcripts.py --self-test
    python3 scripts/check-measurement-transcripts.py --check
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Repo-relative for display; `_read` resolves against the repo root so a run from
# a subdirectory reads the right files instead of raising.
REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_PATH = Path("Pastura/PasturaTests/Views/DesignTokensTests+MutedAsContent.swift")
LEDGER_PATH = Path("docs/design/muted-application-audit.md")
ADR_PATH = Path("docs/decisions/ADR-028.md")
DESIGN_SYSTEM_PATH = Path("docs/design/design-system.md")

FIXTURE_NAME = "DesignTokensTests+MutedAsContent"

OPAQUE_DECL = "private static let opaqueGroundPins"
WASH_DECL = "private static let washRowPins"
# `("name", 3.329)` — the shared shape of the ratio-keyed pin arrays.
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
# En dash, em dash, wave dash, fullwidth tilde, ASCII tilde and hyphen: the docs
# already use two of these (`–` in the English faces, `〜` in the Japanese one),
# so the set is wider than today's text on purpose. The ASCII hyphen is the
# member most likely to produce a false red — any hyphenated numeric pair in an
# anchored block (`3.1-3.2`) reads as a second span.
RANGE = re.compile(r"([0-9]+\.[0-9]+)\s*[–—〜～~-]\s*([0-9]+\.[0-9]+)")
WASH_TABLE_HEADER = re.compile(r"^\|\s*Site\s*\|.*\blight\b.*\bdark\b", re.IGNORECASE)
OPAQUE_TABLE_HEADER = re.compile(r"^\|\s*Light ground\s*\|", re.IGNORECASE)

# Section anchors, named once so `collect` and the self-test cannot drift into
# two spellings of the same pattern.
#
# Two terminators, and the difference is load-bearing. The ledger's faces are
# `###` subsections, so ANY heading ends them — `^#{2,3} ` would let a future
# `#### ` silently extend the slice. The ADR's faces are `##` amendments that
# legitimately CONTAIN `###` subsections (the wash table sits under one), so
# there the terminator must stay `^## ` or the slice ends before the table.
NEXT_SUBSECTION = re.compile(r"^#{1,6} ")
NEXT_SECTION = re.compile(r"^## ")
LEDGER_31 = re.compile(r"^### 3\.1\b")
LEDGER_32 = re.compile(r"^### 3\.2\b")
ADR_WASHES = re.compile(r"^## Amendment 2026-08-15\b")
ADR_SPAN = re.compile(r"^## Amendment 2026-08-13 — the quietude tier\b")
DESIGN_SYSTEM_8 = re.compile(r"^## 8\.")

# ADR-028's copy of the wash table carries four of the five rows. Naming the
# missing one here is what keeps the omission an assertion rather than a hole:
# `compare_wash` reddens both if a named row appears and if an unnamed one goes
# missing.
ADR_OMITS = {"HighlightShareCard"}


class AnchorError(Exception):
    """An extraction anchor stopped matching — the gate cannot judge."""


def _read(path: Path) -> str:
    """Read a tracked input, or raise `AnchorError` naming both edit sites.

    A file going missing is an anchor loss like any other, and the loudest way it
    happens is a rename: the gate script's `TRIGGER` regex then stops matching
    the new path too, so the local gate skips silently and CI is the first thing
    to notice. Letting `FileNotFoundError` escape would surface that as a bare
    traceback, and would falsify this module's own claim that every anchor
    raises.
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


def canonical(value: str) -> str:
    """A decimal at the docs' printed precision, so `2.3` and `2.300` agree."""
    return f"{float(value):.3f}"


def section(text: str, start: re.Pattern[str], nxt: re.Pattern[str], where: str) -> list[str]:
    """The lines of one anchored section, or `AnchorError`."""
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
    return lines[begin:end]


def logical_blocks(lines: list[str]) -> list[str]:
    """Paragraphs and list items, each joined with its continuation lines.

    Hard-wrapped prose read line by line loses whatever crosses the wrap, and the
    span sentence does cross one in two of its three faces. Table rows and
    headings break a block so a table can never merge into the paragraph above
    it — without that, `design-system.md` §8's consecutive bullets would fuse and
    the span anchor would pick up an unrelated bullet's range.
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

    Joined rather than read per line because swift-format wraps a long literal,
    and a wrapped `WashRowPin(` + newline + `site: "…"` read per line vanishes —
    failing with the *inverted* diagnosis ("the docs name a row the fixture
    lacks") and sending the author to edit the wrong file.
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


def ledger_opaque_rows(lines: list[str], where: str) -> dict[str, str]:
    """§3.1's twelve grounds as `{ground name: ratio}`.

    Each row carries a light pair and a dark pair, and the ratio cells carry
    annotations (`← §8's calibration point`, `**2.136**`), so the first decimal
    in the cell is the figure and the rest is prose.
    """
    rows = table_rows(lines, OPAQUE_TABLE_HEADER, where)
    found: dict[str, str] = {}
    for cells in rows:
        # Exact, not a floor: an inserted column shifts the ratio cells, and a
        # `< 4` floor would then read the wrong cell's figure and blame the
        # figures rather than the columns.
        if len(cells) != 4:
            raise AnchorError(f"{where}: a §3.1 row has {len(cells)} cells, expected 4.")
        for name_cell, ratio_cell in ((cells[0], cells[1]), (cells[2], cells[3])):
            name = BACKTICKED.search(name_cell)
            ratio = DECIMAL.search(ratio_cell)
            if not name or not ratio:
                raise AnchorError(
                    f"{where}: a §3.1 row is not `name` + ratio — got "
                    f"{name_cell!r} / {ratio_cell!r}."
                )
            found[name.group(1)] = canonical(ratio.group(0))
    # A repeated ground name would OVERWRITE, dropping the earlier row's figure
    # from a comparison that is set-based and therefore blind to a multiset
    # defect — a stale duplicate row above a correct one would pass. `table_rows`
    # covers the empty case, so this is the only cardinality guard needed here.
    if len(found) != 2 * len(rows):
        raise AnchorError(
            f"{where}: {len(rows)} rows yielded only {len(found)} distinct grounds — "
            "a ground name is repeated, and the duplicate would silently win."
        )
    return found


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

    Because the key is a **truncation**, two rows on the same view would collapse
    onto one entry and the earlier one's figures would never be compared. §3.2 is
    expected to grow — ADR-028 § Amendment 2026-08-15 records batches 2–5 as open,
    and `ResultsView` already ships a second pill state — so the duplicate guard
    below is live, not defensive.
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
    omits: set[str],
) -> list[str]:
    """Per-row comparison. `omits` names the pins this face deliberately lacks.

    An `omits` **set** rather than a subset flag: a flag has no cardinality
    floor, so the ADR table could shrink to a single row and stay green, and the
    docstring's checkable claim ("four of the five rows, no `HighlightShareCard`")
    would go unexecuted. Naming the omission turns that claim into the assertion,
    and reddens if `HighlightShareCard` is ever added there without updating this
    checker.
    """
    problems = []
    for site in sorted(set(doc) - set(pins)):
        problems.append(f"{where}: `{site}` is transcribed but is not a pin — drop it or pin it.")
    missing = set(pins) - set(doc)
    for site in sorted(missing - omits):
        problems.append(f"{where}: `{site}` is pinned but is not transcribed — add the row.")
    for site in sorted(omits - missing):
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
    adr_omits: set[str] = ADR_OMITS,
) -> list[str]:
    """Every divergence across the four faces.

    `adr_omits` is a parameter so the self-test can give the ADR face content the
    ledger face does not have. When the two synthetic faces were byte-identical,
    both the direction asymmetry and the face wiring were unguarded: flipping the
    ADR comparison to the bijection direction, and repointing it at the ledger's
    own section, each left the suite fully green.
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
    return problems


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
    print("measurement-transcript gate: clean (4 faces mirrored)")
    return 0


# --- self-test fixtures -----------------------------------------------------
#
# Synthetic figures throughout, never the real ones: these fixtures are
# self-consistent, so real values here would add decoy hits to any future
# value-shaped sweep of the tree — the very sweep this gate replaces.

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
    "Pinned by `DesignTokensTests+MutedAsContent`; §8 carries the same span.\n"
    "`muted` runs **9.111–9.777** across them.\n"
)

# A sibling bullet carrying its own range and NOT naming the fixture. Live
# control for the span anchor in the design-system arm: loosen the block anchor
# and this range is picked up, so the arm reddens.
#
# Three properties are load-bearing and each cost a bug to learn:
#
# - **Synthetic figures.** An earlier revision used `4.413〜4.773 … #1408`, which
#   is live shipped text in `design-system.md` four times over — refuting the
#   "never the real ones" rule stated 20 lines above it.
# - **Wave dash, not en dash.** The real `design-system.md` §8 spells its span
#   with `〜`, and this decoy's whole discriminating power depends on `RANGE`
#   still admitting that character. `waveDashRangeIsRead` below asserts it, so
#   narrowing `RANGE` reddens the harness instead of quietly inerting the decoy.
# - **Adjacent to the span block, with no blank line between.** The real §8 is a
#   solid blank-line-free bullet list, so only the `LIST_ITEM` flush separates
#   the span-bearing bullet from this one. With a blank line here, deleting that
#   flush from `logical_blocks` left the suite fully green — its docstring was
#   right about production and untested by the fixture.
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


def synth_ledger(opaque: str = SYNTH_OPAQUE_TABLE, wash: str = SYNTH_WASH_TABLE) -> str:
    return (
        "## 3. Grounds\n\n"
        "### 3.1 The twelve opaque grounds\n\n" + SYNTH_SPAN_BLOCK + "\n" + opaque + "\n"
        "### 3.2 Composited grounds\n\n" + wash + "\n"
        "### 3.3 Grounds that are not computable\n\nprose\n"
    )


# The ADR face must NOT be a byte-identical copy of the ledger's. When it was,
# two independent wirings went unguarded and both stayed green under mutation:
# flipping the ADR comparison to the bijection direction, and repointing it at
# the ledger's own section. Omitting `BetaSite` here exercises the real
# asymmetry — ADR-028 carries four of the five rows — and gives the two faces
# distinguishable content, so a face-identity arm can exist at all.
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
        "## Amendment 2026-08-15 — the second unmeasured ground (#1448)\n\n" + wash + "\n"
        "## Related\n\nprose\n"
    )


def synth_design_system(span: str = SYNTH_SPAN_BLOCK) -> str:
    # No blank line before the decoy: see `SYNTH_DECOY_RANGE`. The real §8's
    # bullets are adjacent, so only the `LIST_ITEM` flush separates them, and a
    # blank line here would test a branch production never takes.
    return (
        "## 7. Copywriting\n- unrelated\n\n"
        "## 8. Accessibility\n\n" + span + SYNTH_DECOY_RANGE + "\n"
        "## 9. Rollout\n- unrelated\n"
    )


def self_test() -> int:
    """Positive and negative controls.

    A guard whose success case is its only evidence proves nothing. Every arm
    below asserts an **exact** value rather than merely flagged/clean, so a decoy
    leaking into an extractor is caught by that extractor's own arm and not only
    by whichever comparison happens to notice.
    """
    failures = 0
    checked = 0

    def fail(name: str, detail: str) -> None:
        nonlocal failures
        print(f"self-test FAILED: {name} — {detail}", file=sys.stderr)
        failures += 1

    def expect(name: str, thunk, want: object) -> None:
        """`thunk`, not a value: an unexpected `AnchorError` raised while
        building the argument would otherwise escape uncaught, aborting every
        remaining arm with a traceback and no tally — losing the run's whole
        diagnostic value at the moment it is most needed.
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

        Without it an arm passes off any neighbouring anchor, and a mutation that
        missed its target reads as coverage. Measured, not hypothetical: the
        emptied-array arm below fired `_decl_block`'s bracket anchor instead of
        the empty-set one, because deleting the rows also deleted the closing
        bracket's indentation.
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
    # swift-format wraps a long literal. Read per line the wrapped row vanishes,
    # and the gate then fails with the INVERTED diagnosis — "the docs name a row
    # the fixture lacks" — sending the author to edit the wrong file.
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
    # Each of these would otherwise collapse to an empty set and compare "equal"
    # against the other side — a green gate that judged nothing.

    expect_raises(
        "fixture: the ratio-pin declaration was renamed",
        "no 'private static let opaqueGroundPins' declaration",
        lambda: fixture_ratio_pins(SYNTH_FIXTURE.replace("opaqueGroundPins", "groundPins")),
    )
    expect_raises(
        "fixture: the ratio-pin array was emptied",
        'yielded no `("name", ratio)` rows',
        # The rows are replaced by a comment rather than deleted: deleting them
        # also deletes the closing bracket's indentation, and the arm then
        # reddens off `_decl_block`'s anchor instead of the empty-set one — a
        # pass for the wrong reason, which is indistinguishable from a real one.
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
    # The other direction of the same assertion: a face that GAINS a row this
    # checker still records as deliberately absent must redden too, or
    # `HighlightShareCard` could be added to ADR-028 and silently go unchecked.
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
    # Face identity. With the two synthetic faces byte-identical, repointing the
    # ADR comparison at the ledger's own section left the suite green — there was
    # nothing to tell the faces apart. These two arms pin the label on a mutation
    # that only the ADR text carries.
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

    # `SYNTH_DECOY_RANGE` is wave-dash separated, like the real `design-system.md`
    # §8 span. Narrow `RANGE` to `[–—]` and the decoy silently stops being a
    # control — with no arm here, the suite stayed green through that narrowing.
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
    # `canonical` exists so `2.3` and `2.300` agree; every other fixture writes
    # three digits on both sides, so without this arm it is only ever identity.
    expect(
        "canonical: a doc cell at fewer digits still matches a three-digit pin",
        lambda: ledger_opaque_rows(
            ledger_section(r"^### 3\.1", ledger.replace("| 9.111 ←", "| 9.11 ←")),
            "ledger §3.1",
        ),
        {"alphaGround": "9.110", "betaGround": "9.777"},
    )
    # A pin written as an integer literal is legal Swift for a `Double`. Unmatched,
    # the row vanished from the extracted dict and the gate blamed the DOC —
    # the inverted diagnosis, sending the author to edit the file that did not change.
    expect(
        "fixture: an integer pin literal is read, not dropped",
        lambda: fixture_ratio_pins(SYNTH_FIXTURE.replace('("betaGround", 9.777)', '("betaGround", 9)')),
        {"alphaGround": "9.111", "betaGround": "9.000"},
    )

    # --- cardinality guards --------------------------------------------------
    #
    # Both keys are lossy — a ground name straight from the cell, a site key
    # truncated to its leading identifier — so a repeat OVERWRITES and the earlier
    # row's figures are never compared. The bijections downstream are set-based
    # and structurally cannot see a multiset defect.

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

    if failures:
        return 1
    print(f"measurement-transcript self-test: {checked}/{checked} passed")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        rc = self_test()
        if rc or not args.check:
            return rc
    if args.check:
        return check()
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
