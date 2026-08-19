#!/usr/bin/env python3
"""Guard: design-system §8's closing sub-bullet and the `mossInkWashSites`
fixture name the **same set** of rows.

Why this exists. §8's closing sub-bullet quotes the fixture's row names and
adjudicates each against §8's four-condition exception. It states outright that
the fixture is the membership authority and that the names written there are
"today's copy" — but nothing enforced that. A third row added to
`mossInkWashSites` left the bullet stale with nothing to notice (#1467).

Same failure class as ADR-028 § "Count-mirror sweep", one step weaker. #1466
removed the *count* from that bullet on exactly those grounds; naming escapes
the digit, not the mirror. That sweep's command matches counts spelled `seven`
or a digit + `sites`, so run verbatim it returns nothing for a name set — "I
re-ran the sweep" keeps reading clean while this mirror rots.

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

The doc must spell a row as `"Row.name"` **in backticks** — that is the form the
bullet already uses, and the only form read here. A name written without it goes
missing from the doc set and the gate fails; the message below says so.

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
sub-bullet anchor, a missing declaration, or an empty extracted set each raises
instead of collapsing into an empty-vs-empty "equal" pass.

Trigger paths (mirrored by scripts/mossink-wash-membership-precommit-gate.sh):
    docs/design/design-system.md
    Pastura/PasturaTests/Views/DesignTokensTests+MossInkAsWashLabel.swift
    scripts/check-mossink-wash-membership.py

Usage:
    python3 scripts/check-mossink-wash-membership.py --self-test
    python3 scripts/check-mossink-wash-membership.py --check
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DOC_PATH = Path("docs/design/design-system.md")
FIXTURE_PATH = Path(
    "Pastura/PasturaTests/Views/DesignTokensTests+MossInkAsWashLabel.swift"
)

SECTION_HEADING = re.compile(r"^## 8\.")
NEXT_SECTION = re.compile(r"^## ")
# Indented list item — the closing sub-bullet. A top-level `- ` is NOT an anchor.
SUB_BULLET = re.compile(r"^[ \t]+- ")
DOC_ANCHOR = "DesignTokensTests+MossInkAsWashLabel"
# Backtick + ASCII double quote on both sides. `GameHeaderStatus.completed` in
# bare backticks must not match, nor `role="status" aria-live="polite"`.
QUOTED_ROW = re.compile(r"`\"([^\"`]+)\"`")

FIXTURE_DECL = "static var mossInkWashSites"
FIXTURE_ROW = re.compile(r"MossWashSite\(\s*\"([^\"]+)\"")


class AnchorError(Exception):
    """An extraction anchor stopped matching — the gate cannot judge."""


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
        line
        for line in lines[start:end]
        if SUB_BULLET.match(line) and DOC_ANCHOR in line
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
            '`"Row.name"` form (backticks around the quoted string).'
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
            f"  Named in §8 but NOT in {FIXTURE_PATH} — drop the name from the "
            'sub-bullet, or check it is spelled `"Row.name"` in backticks '
            "(the only form read):",
            file=sys.stderr,
        )
        for name in sorted(only_doc):
            print(f"    {name}", file=sys.stderr)


def check() -> int:
    try:
        doc = doc_row_names(DOC_PATH.read_text(encoding="utf-8"))
        fixture = fixture_row_names(FIXTURE_PATH.read_text(encoding="utf-8"))
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
# The synthetic doc keeps two decoys in every case rather than only in the arm
# that names them: the top-level §8 bullet that also mentions the fixture (the
# anchor must skip it) and the `role="status" aria-live="polite"` bullet (a
# quoted string that is not a row name). A decoy present only in its own arm
# stops covering the arms it was meant to protect.

TOP_LEVEL_MENTION = (
    "- ⚠️ The sweep behind `DesignTokensTests+MossInkAsWashLabel` is "
    "manual, and `HomePausedCard`'s progress label was repointed in #1459\n"
)
ARIA_DECOY = '- Progress uses `role="status" aria-live="polite"`\n'

TWO_ROWS = (
    '      MossWashSite("GameHeader.statusPill", wash: .mossDark, light: 0.14, dark: 0.14),\n'
    '      MossWashSite("ResultsView.completed", wash: .moss, light: 0.16, dark: 0.16)\n'
)
BASELINE = {"GameHeader.statusPill", "ResultsView.completed"}


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
        '    let failing = Self.mossInkWashSites.filter { $0.name == "GameHeader.statusPill" }\n'
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

    def fail(name: str, detail: str) -> None:
        nonlocal failures
        print(f"self-test FAILED: {name} — {detail}", file=sys.stderr)
        failures += 1

    def expect_set(name: str, got: set[str], want: set[str]) -> None:
        if got != want:
            fail(name, f"expected {sorted(want)}, got {sorted(got)}")

    # --- extraction ---------------------------------------------------------

    # A bare-backtick identifier is not a row name. `Phantom.row` is the control:
    # if the doc regex ever stopped requiring the surrounding quotes, it appears.
    expect_set(
        "doc: only backtick-plus-quote names are rows",
        doc_row_names(
            _doc(
                TOP_LEVEL_MENTION
                + _sub_bullet(
                    'Read `"GameHeader.statusPill"` (= `GameHeaderStatus.completed`) '
                    'and `"ResultsView.completed"` row by row; `Phantom.row` is an '
                    'identifier, not a row, and a bare "quoted phrase" is not one '
                    "either"
                )
                + ARIA_DECOY
            )
        ),
        BASELINE,
    )

    # The anchor is the indented sub-bullet only. A top-level §8 line naming the
    # fixture discusses a REMOVED row (#1459) — it must contribute nothing even
    # when it carries the quoted form.
    expect_set(
        "doc: a top-level anchor mention contributes nothing",
        doc_row_names(
            _doc(
                TOP_LEVEL_MENTION.rstrip("\n")
                + ' and `"TopLevel.phantom"`\n'
                + _sub_bullet('`"GameHeader.statusPill"` and `"ResultsView.completed"`')
                + ARIA_DECOY
            )
        ),
        BASELINE,
    )

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
    both_named = _sub_bullet('`"GameHeader.statusPill"` and `"ResultsView.completed"`')
    three_named = _sub_bullet(
        '`"GameHeader.statusPill"`, `"ResultsView.completed"` and `"NewSite.pill"`'
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
                + _sub_bullet("the rows are ResultsView.completed and the pill")
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

    total = 4 + len(comparisons) + len(anchor_cases)
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
