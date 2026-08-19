#!/usr/bin/env python3
r"""Guard: design-system §8's closing sub-bullet and the `mossInkWashSites`
fixture name the **same set** of rows.

§8's closing sub-bullet quotes the fixture's row names and adjudicates each
against §8's four-condition exception, declaring the fixture the membership
authority and its own names "today's copy" — with nothing enforcing that.

**Re-running ADR-028 § "Count-mirror sweep" does not reach this mirror.** That
sweep matches counts spelled `seven` or a digit + `sites`; a name set escapes
the digit, so the sweep returns nothing here and "I re-ran it" keeps reading
clean while the mirror rots.

Why set equality rather than subset, and why the direction matters. Doc-subset-
of-fixture catches §8 naming a row the fixture dropped but misses the **add**
case; fixture-subset-of-doc catches the add but misses the stale name. The add
case is the one #1467 is about, and both are the same comparison, so the
assertion is equality.

**What this does NOT certify.** Green means the two *name sets* match. It says
nothing about whether each row's adjudication in §8 is current or correct — the
bullet's whole point is that the rows carry **different** reasons (one is
condition (2)'s precedent itself; the other is barred by the carve-out from ever
becoming the next site's precedent), and it explicitly forbids summarising them
as a set. An author who pastes a bare third name into the bullet turns this gate
green with no adjudication written. That is the bound §8 already states for
`MutedSweepLedgerTests`: green means "the set matches the snapshot", no more.
Nor does it detect a new `mossInk`-on-moss-wash **site in the app** — the §8
bullet above the closing one records that no such detector exists, and this gate
does not change that.

Doc-side anchor. Read §8 (`## 8.` through the next `## `), then the **indented
sub-bullets** there that mention `DesignTokensTests+MossInkAsWashLabel`.
Deliberately not every §8 line mentioning the fixture: the top-level bullet just
above the closing one also names it, and that bullet discusses
`HomePausedCard.progress` — a row #1459 *removed* from `mossInkWashSites`. One
future edit writing that name in the quoted row form would inject a phantom
member and red this gate over a bullet whose job is not to mirror the fixture.

The doc must spell a row as `"Row.name"` — **backticks, quotes, and an
identifier-shaped token inside**, the form the bullet already uses and the only
one read here. That is also the **escape hatch**: to write *about* a row the
fixture no longer carries, mention it in any other form and it stays invisible
to the gate. The `only_doc` message says so, because "you typo'd" is the wrong
advice in that case.

`mossWashSites` ships a dotless row (`PhaseTypeLabel`), so the shape admits one;
requiring a dot would make the next such row silently invisible.

Anchored sub-bullets are joined with their markdown continuation lines before
matching, so a hard-wrapped bullet keeps its names — same treatment, and same
reason, as the fixture block below.

**This is the only set-shaped mirror as of #1467, and that is a measurement, not
a property.** Do not re-assert it from this paragraph — re-run the enumeration,
which is name-shaped where ADR-028's is count-shaped:

```sh
git grep -nE '"(GameHeader\.statusPill|ResultsView\.completed)"|mossInkWashSites'
```

Every other hit today is a single-name cross-reference or a pointer to the
fixture, not a copy of the set. The self-test fixtures below use synthetic names
so they do not pollute that sweep.

Fixture-side scope. The `static var mossInkWashSites` declaration only — its
line through the first following line whose stripped content is `}` at the same
indentation — because the same name strings also appear in `.filter { $0.name
== … }` arms further down that file. Extraction runs over the **joined** block
text rather than line by line, so a swift-format-wrapped `MossWashSite(` +
newline + `"Name",` is still read. The sibling fixture already ships that shape
and the ink rows sit close to the column limit, so the next row added may take
it. Reading per line would fail with the *inverted* diagnosis ("§8 names a row
the fixture lacks") and send the author to edit the wrong file — the wrapped-row
self-test arm is what bars that.

Every anchor is asserted rather than allowed to degrade: a missing §8, a missing
sub-bullet anchor, a missing declaration, an empty extracted set, or an
**unreadable input file** each raises instead of collapsing into an
empty-vs-empty "equal" pass or a bare traceback.

Trigger paths live in `scripts/mossink-wash-membership-precommit-gate.sh`, which
is what self-gates on them — one copy, so the two cannot drift.

Usage:
    python3 scripts/check-mossink-wash-membership.py --self-test
    python3 scripts/check-mossink-wash-membership.py --check
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Repo-relative for display; `_read` resolves against the repo root so a run
# from a subdirectory reads the right files instead of raising.
REPO_ROOT = Path(__file__).resolve().parent.parent
DOC_PATH = Path("docs/design/design-system.md")
FIXTURE_PATH = Path(
    "Pastura/PasturaTests/Views/DesignTokensTests+MossInkAsWashLabel.swift"
)

SECTION_HEADING = re.compile(r"^## 8\.")
NEXT_SECTION = re.compile(r"^## ")
# Indented list item — the closing sub-bullet. A top-level `- ` is NOT an anchor.
SUB_BULLET = re.compile(r"^[ \t]+- ")
# Any list item, at any indent: terminates a bullet's continuation lines.
LIST_ITEM = re.compile(r"^[ \t]*([-*+]|[0-9]+\.)[ \t]")
DOC_ANCHOR = "DesignTokensTests+MossInkAsWashLabel"
# Backtick + ASCII double quote on both sides, wrapping an **identifier-shaped**
# token. Three things must not match, and each has a live self-test control:
# `GameHeaderStatus.completed` in bare backticks (no quotes), a bare
# "BareQuoted.token" (no backticks), and `"Round X / Y"` — a quoted UI string in
# §8's prose, which the surrounding bullets do discuss. Without the shape
# constraint that last one becomes a phantom member and reds the gate over prose
# that is correct. The constraint admits a dotless name: `mossWashSites` ships
# `PhaseTypeLabel`, so requiring a dot would make the next such row invisible.
QUOTED_ROW = re.compile(r"`\"([A-Za-z_][A-Za-z0-9_.]*)\"`")

FIXTURE_DECL = "static var mossInkWashSites"
FIXTURE_ROW = re.compile(r"MossWashSite\(\s*\"([^\"]+)\"")


class AnchorError(Exception):
    """An extraction anchor stopped matching — the gate cannot judge."""


def _read(path: Path) -> str:
    """Read a tracked input, or raise `AnchorError` naming both edit sites.

    A **file** going missing is an anchor loss like any other, and the loudest
    way it happens is a rename: the gate script's `TRIGGER` regex then no longer
    matches the new path either, so the local gate silently skips and CI is the
    first thing to notice. Letting `FileNotFoundError` escape would surface that
    as a bare traceback — and would falsify this module's own claim that every
    anchor raises rather than degrading.
    """
    try:
        return (REPO_ROOT / path).read_text(encoding="utf-8")
    except OSError as exc:
        raise AnchorError(
            f"{path}: cannot read it ({exc.strerror}). If it was renamed, update "
            "BOTH this checker's path constant AND the TRIGGER regex in "
            "scripts/mossink-wash-membership-precommit-gate.sh — otherwise the "
            "local gate stops matching the new path and skips silently."
        ) from exc


def _logical_line(lines: list[str], index: int, end: int) -> str:
    """The list item at `index` joined with its markdown continuation lines.

    Mirrors `fixture_row_names`' joined-block treatment, for the same reason and
    against the same hazard: a hard-wrapped sub-bullet read line by line drops
    every row name on a continuation line, and the gate then fails with the
    *inverted* diagnosis ("§8 names a row the fixture lacks" → author edits the
    wrong file). §8's bullets are unwrapped today and nothing in the repo forbids
    wrapping one, so this is a tripwire on the next editor, not a fit to the
    current text. Lazy continuation (an unindented wrapped line) is accepted too
    — markdown allows it, and rejecting it would drop names for a reason the
    author cannot see.
    """
    parts = [lines[index]]
    for j in range(index + 1, end):
        nxt = lines[j]
        if not nxt.strip() or LIST_ITEM.match(nxt) or nxt.startswith("#"):
            break
        parts.append(nxt.strip())
    return " ".join(parts)


def doc_row_names(text: str) -> set[str]:
    """Row names §8's closing sub-bullet claims, as a set."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if SECTION_HEADING.match(line):
            start = i
            break
    if start is None:
        raise AnchorError(
            f"{DOC_PATH}: no '## 8.' heading — the section this gate mirrors "
            "was renumbered or renamed."
        )
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if NEXT_SECTION.match(lines[i]):
            end = i
            break

    anchors = [
        _logical_line(lines, i, end)
        for i in range(start, end)
        if SUB_BULLET.match(lines[i]) and DOC_ANCHOR in lines[i]
    ]
    if not anchors:
        raise AnchorError(
            f"{DOC_PATH}: §8 has no indented sub-bullet mentioning "
            f"'{DOC_ANCHOR}'. The closing bullet moved, was un-indented, or "
            "stopped naming the fixture."
        )

    names: set[str] = set()
    for line in anchors:
        names.update(QUOTED_ROW.findall(line))
    if not names:
        raise AnchorError(
            f"{DOC_PATH}: the §8 sub-bullet names no row in the required "
            '`"Row.name"` form (backticks around the quoted string, and an '
            "identifier-shaped token inside it)."
        )
    return names


def fixture_row_names(text: str) -> set[str]:
    """Row names the `mossInkWashSites` declaration carries, as a set."""
    lines = text.splitlines()
    decl = None
    for i, line in enumerate(lines):
        if FIXTURE_DECL in line:
            decl = i
            break
    if decl is None:
        raise AnchorError(
            f"{FIXTURE_PATH}: no '{FIXTURE_DECL}' declaration — the membership "
            "authority was renamed or moved."
        )
    indent = len(lines[decl]) - len(lines[decl].lstrip())
    end = None
    for i in range(decl + 1, len(lines)):
        stripped = lines[i].strip()
        if stripped == "}" and (len(lines[i]) - len(lines[i].lstrip())) == indent:
            end = i
            break
    if end is None:
        raise AnchorError(
            f"{FIXTURE_PATH}: could not find the closing brace of "
            f"'{FIXTURE_DECL}' at its own indentation."
        )

    # Joined, not per line: a wrapped `MossWashSite(` + newline + `"Name",` must
    # still be read (see the module docstring).
    block = "\n".join(lines[decl : end + 1])
    names = set(FIXTURE_ROW.findall(block))
    if not names:
        raise AnchorError(
            f"{FIXTURE_PATH}: '{FIXTURE_DECL}' yielded no MossWashSite rows — "
            "the row shape changed, or the fixture was emptied."
        )
    return names


def divergence(doc: set[str], fixture: set[str]) -> tuple[set[str], set[str]]:
    """(rows only the fixture has, rows only §8 has)."""
    return fixture - doc, doc - fixture


def _report(only_fixture: set[str], only_doc: set[str]) -> None:
    print(
        "mossink-wash-membership gate: design-system §8's closing sub-bullet "
        "and `mossInkWashSites` name different rows.\n"
        "The fixture is the membership authority; §8's names are its copy "
        "(#1467).\n",
        file=sys.stderr,
    )
    if only_fixture:
        print(
            f"  In {FIXTURE_PATH} but NOT named in §8 — add the row to the "
            "closing sub-bullet WITH its own four-condition adjudication (§8 "
            "forbids summarising the rows as a set):",
            file=sys.stderr,
        )
        for name in sorted(only_fixture):
            print(f"    {name}", file=sys.stderr)
    if only_doc:
        print(
            f"  Named in §8 but NOT in {FIXTURE_PATH} — the fixture is the "
            "authority, so drop the name from the sub-bullet rather than adding "
            "the row. To write ABOUT a row the fixture no longer carries "
            "(`HomePausedCard.progress` is the precedent), mention it in any "
            'form other than `"Row.name"` in backticks — that is the only form '
            "read here, so anything else is deliberately invisible to this "
            "gate:",
            file=sys.stderr,
        )
        for name in sorted(only_doc):
            print(f"    {name}", file=sys.stderr)


def check() -> int:
    try:
        doc = doc_row_names(_read(DOC_PATH))
        fixture = fixture_row_names(_read(FIXTURE_PATH))
    except AnchorError as exc:
        print(f"mossink-wash-membership gate: {exc}", file=sys.stderr)
        print(
            "Fix the anchor (or this checker) — the gate refuses to pass "
            "without judging.",
            file=sys.stderr,
        )
        return 1
    only_fixture, only_doc = divergence(doc, fixture)
    if only_fixture or only_doc:
        _report(only_fixture, only_doc)
        return 1
    print(
        f"mossink-wash-membership gate: clean ({len(doc)} rows mirrored)"
    )
    return 0


# --- self-test fixtures -----------------------------------------------------
#
# The synthetic doc mirrors the real §8's neighbourhood, but only ONE of its two
# props is a live control — say which, because a prop that cannot redden reads
# like coverage:
#
# - `TOP_LEVEL_MENTION` IS live, in every arm that reaches the sub-bullet
#   anchor — measured: all but `§8 renumbered away`, where the *section* anchor
#   raises first and nothing below it runs. It is a column-0 bullet naming the
#   fixture and carrying a row name in the quoted form, so loosening the
#   sub-bullet anchor pulls `TopLevel.phantom` into the expected set. It is
#   shared rather than local to one arm precisely so the anchor stays
#   constrained everywhere it can be.
# - `ARIA_DECOY` is NOT a control. It is realism — the real §8 carries
#   `role="status" aria-live="polite"` as a sibling bullet in the same section
#   — and being column-0 it is dropped by the anchor before `QUOTED_ROW` ever
#   sees it. The live control for the row-name form is inside the sub-bullet of
#   the first arm below (a bare-backtick identifier and a bare quoted phrase).

TOP_LEVEL_MENTION = (
    "- ⚠️ The sweep behind `DesignTokensTests+MossInkAsWashLabel` is manual, and "
    '`HomePausedCard`\'s `"TopLevel.phantom"` label was repointed in #1459\n'
)
ARIA_DECOY = '- Progress uses `role="status" aria-live="polite"`\n'

# Synthetic row names, never the two real ones: these fixtures are self-
# consistent, so real names here would only add decoy hits to a future
# name-shaped sweep of the kind § "Doc-side anchor" invites.
TWO_ROWS = (
    '      MossWashSite("FirstView.pill", wash: .mossDark, light: 0.14, dark: 0.14),\n'
    '      MossWashSite("SecondView.done", wash: .moss, light: 0.16, dark: 0.16)\n'
)
BASELINE = {"FirstView.pill", "SecondView.done"}


def _sub_bullet(names_md: str) -> str:
    return (
        "  - **`DesignTokensTests+MossInkAsWashLabel` is not an allowlist.** "
        + names_md
        + "\n"
    )


def _doc(section_body: str) -> str:
    return (
        "## 7. Copywriting\n"
        "- unrelated\n"
        "\n"
        "## 8. Accessibility\n"
        "\n" + section_body + "\n"
        "## 9. Rollout guide\n"
        "- unrelated\n"
    )


def _fixture(rows: str, tail: str = "") -> str:
    return (
        "extension DesignTokensTests {\n"
        "\n"
        "  /// One row per shipped site.\n"
        "  static var mossInkWashSites: [MossWashSite] {\n"
        "    [\n" + rows + "    ]\n"
        "  }\n"
        "\n"
        "  @Test func onlyTheStatusPillWasFailingBeforeThisChange() {\n"
        '    let failing = Self.mossInkWashSites.filter { $0.name == "FirstView.pill" }\n'
        + tail
        + "    #expect(failing.count == 1)\n"
        "  }\n"
        "}\n"
    )


def self_test() -> int:
    """Positive and negative controls.

    A guard whose success case is its only evidence proves nothing. Each
    extraction arm below asserts the **exact** set rather than merely
    flagged/clean, so a decoy that started leaking in is caught by that arm and
    not only by whichever comparison happens to notice.
    """
    failures = 0
    # Derived, never hand-maintained: the printed tally is itself a claim about
    # how much ran, so a new arm must not be able to leave it stale. It counts
    # extraction arms only via `expect_set` — assert through it, or the tally
    # under-counts and the staleness is back one indirection further in.
    extraction_arms = 0

    def fail(name: str, detail: str) -> None:
        nonlocal failures
        print(f"self-test FAILED: {name} — {detail}", file=sys.stderr)
        failures += 1

    def expect_set(name: str, got: set[str], want: set[str]) -> None:
        nonlocal extraction_arms
        extraction_arms += 1
        if got != want:
            fail(name, f"expected {sorted(want)}, got {sorted(got)}")

    # --- extraction ---------------------------------------------------------

    # Three live controls, all inside the sub-bullet where `QUOTED_ROW` can
    # reach them — one per conjunct of the row-name form. Drop the quote
    # requirement and `Phantom.row` appears; drop the backtick requirement and
    # `BareQuoted.token` does; drop the identifier shape and `Round X / Y` does.
    expect_set(
        "doc: a row name is backticks + quotes + an identifier-shaped token",
        doc_row_names(
            _doc(
                TOP_LEVEL_MENTION
                + _sub_bullet(
                    'Read `"FirstView.pill"` (= `SecondStatus.done`) and '
                    '`"SecondView.done"` row by row; `Phantom.row` is an identifier, '
                    'not a row, a bare "BareQuoted.token" is not one either, and the '
                    '`"Round X / Y"` label this bullet discusses is prose'
                )
                + ARIA_DECOY
            )
        ),
        BASELINE,
    )

    # Hard-wrapped sub-bullet: the doc side joins continuation lines for the same
    # reason the fixture side joins its block. Read per line, `SecondView.done`
    # vanishes and the gate fails with the INVERTED diagnosis.
    expect_set(
        "doc: a hard-wrapped sub-bullet keeps the names on its continuation lines",
        doc_row_names(
            _doc(
                TOP_LEVEL_MENTION
                + _sub_bullet('Read `"FirstView.pill"` row by row,')
                + '    and `"SecondView.done"` likewise\n'
                + ARIA_DECOY
            )
        ),
        BASELINE,
    )

    # No separate arm for the sub-bullet anchor: `TOP_LEVEL_MENTION` carries
    # `"TopLevel.phantom"` in EVERY doc arm above and below, so loosening the
    # anchor reddens all of them rather than one.

    # Block scoping: a `MossWashSite(...)` outside the declaration, and the
    # `.filter` name strings, must not leak in.
    expect_set(
        "fixture: rows outside the declaration do not leak",
        fixture_row_names(
            _fixture(
                TWO_ROWS,
                tail='    _ = MossWashSite("Sibling.row", wash: .moss, light: 0.1, dark: 0.1)\n',
            )
        ),
        BASELINE,
    )

    # Joined-block extraction: swift-format wraps a long constructor, and the
    # sibling fixture already ships that shape. Read per line this row vanishes
    # and the gate fails with the INVERTED diagnosis.
    expect_set(
        "fixture: a swift-format-wrapped row is still read",
        fixture_row_names(
            _fixture(
                TWO_ROWS.rstrip("\n")
                + ",\n"
                + "      MossWashSite(\n"
                + '        "Wrapped.row", wash: .moss, light: 0.16, dark: 0.16)\n'
            )
        ),
        BASELINE | {"Wrapped.row"},
    )

    # --- comparison ---------------------------------------------------------

    three_rows = (
        TWO_ROWS.rstrip("\n")
        + ",\n"
        + '      MossWashSite("NewSite.pill", wash: .moss, light: 0.12, dark: 0.12)\n'
    )
    both_named = _sub_bullet('`"FirstView.pill"` and `"SecondView.done"`')
    three_named = _sub_bullet(
        '`"FirstView.pill"`, `"SecondView.done"` and `"NewSite.pill"`'
    )

    comparisons = [
        (
            "a row added to the fixture without updating §8",
            _doc(TOP_LEVEL_MENTION + both_named + ARIA_DECOY),
            _fixture(three_rows),
            {"NewSite.pill"},
            set(),
        ),
        (
            "§8 names a row the fixture does not carry",
            _doc(TOP_LEVEL_MENTION + three_named + ARIA_DECOY),
            _fixture(TWO_ROWS),
            set(),
            {"NewSite.pill"},
        ),
        (
            "the sets agree",
            _doc(TOP_LEVEL_MENTION + both_named + ARIA_DECOY),
            _fixture(TWO_ROWS),
            set(),
            set(),
        ),
    ]
    for name, doc_text, fixture_text, want_fixture_only, want_doc_only in comparisons:
        got_fixture_only, got_doc_only = divergence(
            doc_row_names(doc_text), fixture_row_names(fixture_text)
        )
        if got_fixture_only != want_fixture_only or got_doc_only != want_doc_only:
            fail(
                name,
                f"expected fixture-only {sorted(want_fixture_only)} / doc-only "
                f"{sorted(want_doc_only)}, got {sorted(got_fixture_only)} / "
                f"{sorted(got_doc_only)}",
            )

    # --- anchors ------------------------------------------------------------
    #
    # Each of these would otherwise collapse to an empty set and compare
    # "equal" against the other side — a green gate that judged nothing.

    anchor_cases = [
        (
            "doc: §8 renumbered away",
            doc_row_names,
            "## 9. Accessibility\n" + TOP_LEVEL_MENTION + both_named,
        ),
        (
            "doc: the closing bullet is no longer an indented sub-bullet",
            doc_row_names,
            _doc(TOP_LEVEL_MENTION + both_named.lstrip() + ARIA_DECOY),
        ),
        (
            "doc: the sub-bullet names no row in the required form",
            doc_row_names,
            _doc(
                TOP_LEVEL_MENTION
                + _sub_bullet("the rows are SecondView.done and the pill")
                + ARIA_DECOY
            ),
        ),
        (
            "fixture: the declaration was renamed",
            fixture_row_names,
            _fixture(TWO_ROWS).replace("mossInkWashSites", "mossInkWashRows"),
        ),
        (
            "fixture: the declaration carries no rows",
            fixture_row_names,
            _fixture(""),
        ),
    ]
    for name, extractor, text in anchor_cases:
        try:
            got = extractor(text)
        except AnchorError:
            continue
        fail(name, f"expected AnchorError, got {sorted(got)}")

    # A renamed or deleted input is an anchor loss too, and the one the docstring
    # would otherwise only promise: without `_read` it escapes as a bare
    # `FileNotFoundError`, which is not what the caller catches.
    try:
        _read(Path("docs/design/no-such-file-for-the-self-test.md"))
    except AnchorError:
        pass
    except OSError as exc:  # pragma: no cover — the defect this arm bars
        fail("read: a missing input escapes as OSError", repr(exc))
    else:
        fail("read: a missing input", "expected AnchorError, got a successful read")

    total = extraction_arms + len(comparisons) + len(anchor_cases) + 1
    if failures:
        return 1
    print(f"mossink-wash-membership self-test: {total}/{total} passed")
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
