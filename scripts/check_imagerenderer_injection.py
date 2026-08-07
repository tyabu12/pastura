#!/usr/bin/env python3
"""Guard: an app-target file that constructs a SwiftUI `ImageRenderer` must also
inject `\\.colorScheme` into what it renders.

Why this exists — and why it is a *different* predicate from the three guards
ADR-028 § "Revisit trigger" bullet 1 refused. Those all tried to catch a paired
`Color.*` alias being read inside a fixed-appearance export. #1337 measured that
an alias read there is **not** the hazard: it resolves against the injected
`colorScheme` like any other read, `GraphicsContext` inside a `Canvas` included.

What *is* the hazard, measured in the same pass: an export that injects **nothing**
rasterizes **light**, whatever the device. That is the #1070 bug — a dark-mode
user's share card comes out light, appearance-only, with no diagnostic and no
automated observer (ADR-009 rules out the snapshot test that would be one).

That hazard is expressible as a one-line predicate, which is why it is guarded
where the others are not. The refused enumeration guard could not redden on its
own motivating incident (#1319, a component the card *draws*, which creates no
palette type and appears in no consumer list); this one is not an enumeration at
all. It is a tripwire on the **next** export file — today there is exactly one —
so "over-fitted to the single existing consumer", the objection recorded against
the enumeration guard, does not transfer: the existing consumer is the arm that
must stay green, not the thing being fitted to.

**What this does NOT certify.** It is a syntactic co-occurrence check over one
file. It cannot tell that the injected value is the *right* one, that it reaches
every subview, or that a helper called from elsewhere renders without it. It
buys one thing: a new `ImageRenderer` cannot land with no injection anywhere in
sight. Read ADR-028 § Amendment 2026-08-06 (#1337) before widening it.

Scope note: SwiftUI `ImageRenderer` only. `UIGraphicsImageRenderer` is a UIKit
type that takes no SwiftUI content, so `.environment` does not apply to it — and
because its name *ends with* `ImageRenderer`, a naive substring match flags it.
The negative-control fixture below pins that.

Usage:
    python3 scripts/check_imagerenderer_injection.py --self-test
    python3 scripts/check_imagerenderer_injection.py --check
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# `(?<![A-Za-z0-9_])` is load-bearing: without it `UIGraphicsImageRenderer(`
# matches, and a UIKit renderer would be asked for a SwiftUI environment.
CONSTRUCTS_RENDERER = re.compile(r"(?<![A-Za-z0-9_])ImageRenderer\s*\(")
INJECTS_COLOR_SCHEME = re.compile(r"\.environment\s*\(\s*\\\.colorScheme")

SCAN_ROOT = Path("Pastura/Pastura")


def violations(files: dict[str, str]) -> list[str]:
    """Return the paths that construct an `ImageRenderer` without injecting."""
    out = []
    for path, text in sorted(files.items()):
        if CONSTRUCTS_RENDERER.search(text) and not INJECTS_COLOR_SCHEME.search(text):
            out.append(path)
    return out


def self_test() -> int:
    """Positive and negative controls. A guard whose success case is its only
    evidence proves nothing — the positive control is what shows this can fire."""
    cases = [
        # (name, source, should_be_flagged)
        (
            "positive: constructs a renderer, injects nothing",
            "let r = ImageRenderer(content: card)\nr.scale = 3\n",
            True,
        ),
        (
            "negative: constructs and injects",
            "let card = Card().environment(\\.colorScheme, scheme)\n"
            "let r = ImageRenderer(content: card)\n",
            False,
        ),
        (
            "negative: no renderer at all",
            "struct Foo: View { var body: some View { Text(\"hi\") } }\n",
            False,
        ),
        (
            "negative: UIGraphicsImageRenderer is not a SwiftUI renderer",
            "let r = UIGraphicsImageRenderer(size: size)\n",
            False,
        ),
        (
            "negative: prose mention with no construction",
            "/// `ImageRenderer` does not inherit the ambient environment.\n",
            False,
        ),
        (
            "positive: injection is present but for a different key",
            "let card = Card().environment(\\.locale, loc)\n"
            "let r = ImageRenderer(content: card)\n",
            True,
        ),
    ]
    failures = 0
    for name, source, should_flag in cases:
        flagged = bool(violations({"fixture.swift": source}))
        if flagged != should_flag:
            print(
                f"self-test FAILED: {name} — expected "
                f"{'flagged' if should_flag else 'clean'}, got "
                f"{'flagged' if flagged else 'clean'}",
                file=sys.stderr,
            )
            failures += 1
    if failures:
        return 1
    print(f"imagerenderer-injection self-test: {len(cases)}/{len(cases)} passed")
    return 0


def tracked_swift_sources() -> dict[str, str]:
    listing = subprocess.run(
        ["git", "ls-files", f"{SCAN_ROOT}/**/*.swift", f"{SCAN_ROOT}/*.swift"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    files = {}
    for path in listing:
        try:
            files[path] = Path(path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
    return files


def check() -> int:
    found = violations(tracked_swift_sources())
    if found:
        print(
            "imagerenderer-injection gate: a file constructs a SwiftUI "
            "`ImageRenderer` but injects no `\\.colorScheme`.\n"
            "An export that injects nothing rasterizes LIGHT on any device "
            "(measured, ADR-028 § Amendment 2026-08-06 / #1337) — the #1070 bug.\n"
            "Fix: pass the appearance in explicitly, e.g.\n"
            "    let card = Card(model: m, colorScheme: scheme)\n"
            "        .environment(\\.colorScheme, scheme)\n"
            "Reference consumer: "
            "Pastura/Pastura/Views/Components/HighlightCardImageRenderer.swift\n",
            file=sys.stderr,
        )
        for path in found:
            print(f"  {path}", file=sys.stderr)
        return 1
    print("imagerenderer-injection gate: clean")
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
