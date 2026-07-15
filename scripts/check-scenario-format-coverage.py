#!/usr/bin/env python3
"""Assert the public scenario format spec lists every canonical DSL enum case.

The in-app "Copy Gen Prompt" is compiler-gated: `ScenarioGenerationPrompt`
builds its phase / logic lists from `PhaseType.allCases` / `ScoreCalcLogic`
`.allCases` through no-default switches, so a new case cannot ship without a new
switch arm (the ADR-022 "declare once, projections follow" contract). The web
`format.md` reference is a hand-authored Markdown twin that the compiler cannot
gate, so this script is its projection gate: every `PhaseType` and
`ScoreCalcLogic` rawValue must appear as a backtick token (`` `speak_all` ``) in
BOTH locale Markdown sources. A new phase type therefore fails CI (and the
pre-commit sub-gate) until it lands in the public reference too. See #1120.

The backtick anchor (not the bare word) is deliberate: several rawValues are
plain English words (`vote`, `choose`, `conditional`), so a bare-substring match
would false-pass on incidental prose. Requiring `` `vote` `` ties the assertion
to a structured token.

Usage:
    check-scenario-format-coverage.py [--check]   # default: gate the real files
    check-scenario-format-coverage.py --self-test # validate the checker itself
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
PHASE_SWIFT = REPO / "Pastura" / "Pastura" / "Models" / "PhaseType.swift"
LOGIC_SWIFT = REPO / "Pastura" / "Pastura" / "Models" / "ScoreCalcLogic.swift"
SPEC_MD = [
    REPO / "web" / "src" / "content" / "scenario-format.en.md",
    REPO / "web" / "src" / "content" / "scenario-format.ja.md",
]

# Matches a Swift enum `case <name>` line, optionally with an explicit raw value
# (`case foo = "bar"`). `(?![.])` skips switch-statement `case .foo:` patterns.
# One case per line, matching the current PhaseType.swift / ScoreCalcLogic.swift
# shape; a future comma-joined `case a, b` would under-parse (b dropped) and must
# widen this regex. A String enum's rawValue is the explicit string when present,
# else the case identifier verbatim (`case vote` -> "vote").
_CASE_RE = re.compile(r'^\s*case\s+(?![.])([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*"([^"]+)")?')


def raw_values(swift_path: pathlib.Path) -> list[str]:
    """Parse a Swift String enum file -> the ordered list of raw-value strings."""
    values: list[str] = []
    for line in swift_path.read_text(encoding="utf-8").splitlines():
        match = _CASE_RE.match(line)
        if match:
            identifier, explicit = match.group(1), match.group(2)
            values.append(explicit if explicit else identifier)
    return values


def missing_tokens(text: str, tokens: list[str]) -> list[str]:
    """Return the tokens NOT present as a backtick token `<token>` in text."""
    return [t for t in tokens if f"`{t}`" not in text]


def check() -> int:
    tokens = raw_values(PHASE_SWIFT) + raw_values(LOGIC_SWIFT)
    if len(tokens) < 5:
        print(
            f"coverage gate: parsed only {len(tokens)} enum cases — regex or file "
            "shape drifted; refusing to pass silently.",
            file=sys.stderr,
        )
        return 1

    failures = 0
    for md in SPEC_MD:
        text = md.read_text(encoding="utf-8")
        missing = missing_tokens(text, tokens)
        if missing:
            failures += 1
            rel = md.relative_to(REPO)
            print(
                f"coverage gate: {rel} is missing backtick token(s): "
                f"{', '.join('`' + t + '`' for t in missing)}",
                file=sys.stderr,
            )
    if failures:
        print(
            "\nEvery PhaseType / ScoreCalcLogic rawValue must appear as a backtick "
            "token in each web/src/content/scenario-format.<locale>.md.\n"
            "Add the new case to the format spec (both locales) and re-run.",
            file=sys.stderr,
        )
        return 1

    print(f"coverage gate: all {len(tokens)} DSL tokens present in {len(SPEC_MD)} spec file(s).")
    return 0


def self_test() -> int:
    """Validate the checker: it must pass on a complete doc and fail on a gap."""
    tokens = raw_values(PHASE_SWIFT) + raw_values(LOGIC_SWIFT)
    if len(tokens) < 5:
        print(f"self-test: expected >=5 parsed tokens, got {len(tokens)}", file=sys.stderr)
        return 1

    complete = "\n".join(f"- `{t}` does a thing" for t in tokens)
    if missing_tokens(complete, tokens):
        print("self-test: complete doc reported false positives", file=sys.stderr)
        return 1

    dropped = tokens[0]
    gapped = "\n".join(f"- `{t}` does a thing" for t in tokens[1:])
    # The dropped rawValue also appears as a bare word in this note, proving the
    # backtick anchor rejects bare-word occurrences: mentions {dropped} in prose.
    gapped += f"\n\nprose that mentions {dropped} without backticks."
    miss = missing_tokens(gapped, tokens)
    if miss != [dropped]:
        print(
            f"self-test: gap not detected as expected; missing={miss}, wanted [{dropped}]",
            file=sys.stderr,
        )
        return 1

    print(f"self-test: passed ({len(tokens)} tokens; positive + negative case).")
    return 0


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "--check"
    if mode == "--self-test":
        return self_test()
    if mode in ("--check", ""):
        return check()
    print(f"usage: {argv[0]} [--check|--self-test]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
