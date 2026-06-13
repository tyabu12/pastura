#!/usr/bin/env python3
"""Drift guard for the docs/design/ds/ design-token mirror.

Two checks (CI job: design-tokens-drift; mirrors navigation-map-drift's
job-only posture):

1. **Token inclusion** — every color literal in
   ``Pastura/Pastura/Views/DesignTokens*.swift`` must appear in
   ``docs/design/ds/tokens.css``:
   - ``PasturaColorValue(hex: 0xRRGGBB)`` → ``#RRGGBB`` (case-insensitive).
   - ``PasturaColorValue(red: R/255.0, green: G/255.0, blue: B/255.0,
     opacity: A)`` → ``rgba(R, G, B, A)`` with integer channels. The rgba
     constructor form covers the §2.7 interaction tints and §4.3 shadow
     tints — drift-prone opacity fractions, deliberately NOT excepted.
   The guard is one-directional: tokens.css may carry extra CSS-only
   values (font stacks, composite shadows); Swift may not carry colors
   the mirror lacks. ``EXCEPTIONS`` is reserved for genuinely Swift-only
   values — currently empty.

2. **@dsCard markers** — every ``docs/design/ds/*.html`` first line must
   match the DesignSync card-marker shape
   ``<!-- @dsCard group="..." ... -->`` so the claude.ai Design System
   pane can index the card.

Modes:
  --check       run both checks; nonzero exit on any violation (default)
  --self-test   run embedded regression fixtures
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SWIFT_GLOB = "Pastura/Pastura/Views/DesignTokens*.swift"
TOKENS_CSS = REPO_ROOT / "docs/design/ds/tokens.css"
CARDS_DIR = REPO_ROOT / "docs/design/ds"

# Swift-only color values exempt from the tokens.css inclusion check.
# Reserve for values that genuinely have no CSS-mirror role; document the
# reason inline when adding one.
EXCEPTIONS: set[str] = set()

HEX_RE = re.compile(r"PasturaColorValue\(\s*hex:\s*0x([0-9A-Fa-f]{6})")
# Multi-line tolerant: swift-format breaks the constructor across lines.
RGBA_RE = re.compile(
    r"red:\s*([\d.]+)\s*/\s*255\.0,\s*green:\s*([\d.]+)\s*/\s*255\.0,"
    r"\s*blue:\s*([\d.]+)\s*/\s*255\.0,\s*opacity:\s*([\d.]+)",
    re.S,
)
DSCARD_RE = re.compile(r'^<!-- @dsCard group="[^"]+".*-->\s*$')


def extract_swift_tokens(source: str) -> tuple[set[str], set[str]]:
    """Return (hex tokens like '#RRGGBB' uppercased, rgba strings)."""
    hexes = {f"#{h.upper()}" for h in HEX_RE.findall(source)}
    rgbas = set()
    for red, green, blue, opacity in RGBA_RE.findall(source):
        channels = ", ".join(str(int(float(c))) for c in (red, green, blue))
        rgbas.add(f"rgba({channels}, {format(float(opacity), 'g')})")
    return hexes, rgbas


def check_tokens() -> list[str]:
    css = TOKENS_CSS.read_text(encoding="utf-8") if TOKENS_CSS.exists() else ""
    css_upper = css.upper()
    errors = []
    for swift_path in sorted(REPO_ROOT.glob(SWIFT_GLOB)):
        hexes, rgbas = extract_swift_tokens(swift_path.read_text(encoding="utf-8"))
        rel = swift_path.relative_to(REPO_ROOT).as_posix()
        for token in sorted(hexes | rgbas):
            if token in EXCEPTIONS:
                continue
            present = token.upper() in css_upper if token.startswith("#") else token in css
            if not present:
                errors.append(f"{rel}: {token} missing from docs/design/ds/tokens.css")
    return errors


def check_markers() -> list[str]:
    errors = []
    for card in sorted(CARDS_DIR.glob("*.html")):
        first_line = card.read_text(encoding="utf-8").splitlines()[0:1]
        if not first_line or not DSCARD_RE.match(first_line[0]):
            errors.append(
                f"{card.relative_to(REPO_ROOT).as_posix()}: first line must be a "
                '`<!-- @dsCard group="..." ... -->` marker'
            )
    return errors


def self_test() -> int:
    failures = []

    def check(name: str, condition: bool):
        if not condition:
            failures.append(name)

    hexes, rgbas = extract_swift_tokens(
        "static let moss = PasturaColorValue(hex: 0x8A9A6C)\n"
        "static let x = PasturaColorValue(\n  hex: 0xF3EFE7, opacity: 0.6)\n"
    )
    check("hex: simple + multiline + opacity-arg", hexes == {"#8A9A6C", "#F3EFE7"} and not rgbas)

    # Exact production shape from DesignTokens+ExtendedPalette.swift,
    # including the swift-format line break after the open paren.
    hexes, rgbas = extract_swift_tokens(
        "static let hover = PasturaColorValue(\n"
        "  red: 138.0 / 255.0, green: 154.0 / 255.0, blue: 108.0 / 255.0, opacity: 0.06)\n"
        "static let soft = PasturaColorValue(\n"
        "  red: 90.0 / 255.0, green: 100.0 / 255.0,\n"
        "  blue: 60.0 / 255.0, opacity: 0.2)\n"
    )
    check(
        "rgba: integer channels + g-format opacity",
        rgbas == {"rgba(138, 154, 108, 0.06)", "rgba(90, 100, 60, 0.2)"} and not hexes,
    )

    check("marker: valid", bool(DSCARD_RE.match('<!-- @dsCard group="Colors" -->')))
    check(
        "marker: valid with extras",
        bool(DSCARD_RE.match('<!-- @dsCard group="Components" name="Chat bubble" -->')),
    )
    check("marker: rejects plain comment", not DSCARD_RE.match("<!-- chat bubble card -->"))
    check("marker: rejects missing group", not DSCARD_RE.match("<!-- @dsCard -->"))

    for name in failures:
        print(f"SELF-TEST FAIL: {name}", file=sys.stderr)
    print(f"self-test: {6 - len(failures)}/6 passed")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="run drift checks (default)")
    parser.add_argument("--self-test", action="store_true", help="run embedded fixtures")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    errors = check_tokens() + check_markers()
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        return 1
    print("design-tokens: tokens.css and @dsCard markers up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
