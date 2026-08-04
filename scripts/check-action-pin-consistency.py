#!/usr/bin/env python3
"""Assert every workflow `uses:` is SHA-pinned, and one repo resolves to one SHA.

Two invariants over `.github/workflows/*.yml`, both defending failures that are
invisible at merge time:

1. **Every remote action reference is pinned to a 40-hex commit SHA.** A tag is
   mutable, so a floating `@v4` lets an upstream tag move repoint a CI step.

2. **All references to the same `owner/repo` share one SHA.** GitHub splits a
   multi-action repository into one Dependabot dependency *per sub-action*
   (`github/codeql-action/init` and `.../analyze` are tracked separately), so
   two independent PRs can land the halves at different versions. `codeql-action`
   then refuses to run — "Loaded a configuration file for version 'X', but
   running version 'Y'" — and because that workflow is schedule-only, the repo
   silently stops being scanned until someone reads the next run (#1359).

Invariant 2 is keyed on the *consequence* (the SHAs diverged), not on any one
cause, so it fires whether the divergence came from a hand-edit, a partially
merged Dependabot group, or a `groups:` pattern in `.github/dependabot.yml` that
quietly stopped matching. That last one matters: a pattern matching nothing is
indistinguishable from "no updates available" on a monthly cadence, so the
grouping cannot be trusted to enforce itself.

Non-remote `uses:` values — local composite actions (`./.github/actions/x`) and
container steps (`docker://…`) — take no SHA and are skipped. The repo has none
today; they are handled so adding one does not fail this gate spuriously.

Usage:
    check-action-pin-consistency.py [--check]   # default: gate the real workflows
    check-action-pin-consistency.py --self-test # validate the checker itself
"""
from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW_DIR = REPO / ".github" / "workflows"

# A regex rather than a YAML parse: `uses:` values are always a single scalar on
# one line, and this keeps the gate stdlib-only on the ubuntu runner (no PyYAML).
# Captures the value, then splits it below. `#`-comments after the value (the
# `# v7.0.0` version marker Dependabot maintains) are excluded by \S+.
_USES_RE = re.compile(r"^\s*(?:-\s*)?uses:\s*(\S+)")
_SHA_RE = re.compile(r"^[0-9a-f]{40}$")

# Floor guarding against silent regex drift: if a future YAML shape stops
# matching, an empty parse would otherwise report a clean gate. Well below the
# current count (52) so ordinary workflow churn never trips it.
_MIN_REFS = 20


def parse_refs(text: str, source: str) -> list[tuple[str, str, str, str]]:
    """Extract (source, raw_value, owner_repo, ref) for each remote `uses:` line.

    `owner_repo` is the first two path segments — the Dependabot dependency's
    repository — so `github/codeql-action/init` and `github/codeql-action/analyze`
    collapse to one key. Local and docker references return no entry.
    """
    refs: list[tuple[str, str, str, str]] = []
    for line in text.splitlines():
        match = _USES_RE.match(line)
        if not match:
            continue
        value = match.group(1)
        if value.startswith("./") or value.startswith("docker://"):
            continue
        name, _, ref = value.partition("@")
        segments = name.split("/")
        if len(segments) < 2:
            continue
        refs.append((source, value, "/".join(segments[:2]), ref))
    return refs


def find_problems(refs: list[tuple[str, str, str, str]]) -> list[str]:
    """Return one message per violated invariant. Empty list == clean."""
    problems: list[str] = []

    unpinned = [(src, val) for src, val, _, ref in refs if not _SHA_RE.match(ref)]
    for src, val in unpinned:
        problems.append(f"{src}: `{val}` is not pinned to a 40-hex commit SHA")

    by_repo: dict[str, dict[str, list[str]]] = {}
    for src, _, repo, ref in refs:
        if _SHA_RE.match(ref):
            by_repo.setdefault(repo, {}).setdefault(ref, []).append(src)
    for repo, shas in sorted(by_repo.items()):
        if len(shas) > 1:
            detail = "; ".join(
                f"{sha[:12]} in {', '.join(sorted(set(srcs)))}" for sha, srcs in sorted(shas.items())
            )
            problems.append(
                f"{repo}: {len(shas)} different SHAs pinned across workflows — {detail}"
            )
    return problems


def check() -> int:
    refs: list[tuple[str, str, str, str]] = []
    for path in sorted(WORKFLOW_DIR.glob("*.yml")):
        refs += parse_refs(path.read_text(encoding="utf-8"), path.name)

    if len(refs) < _MIN_REFS:
        print(
            f"action-pin gate: parsed only {len(refs)} action references (expected "
            f">={_MIN_REFS}) — the regex or workflow shape drifted; refusing to pass "
            "silently.",
            file=sys.stderr,
        )
        return 1

    problems = find_problems(refs)
    if problems:
        for problem in problems:
            print(f"action-pin gate: {problem}", file=sys.stderr)
        print(
            "\nEvery `uses:` must pin a 40-hex commit SHA, and all references to one\n"
            "repository must pin the SAME SHA. A split repo (github/codeql-action/init\n"
            "vs .../analyze) is two Dependabot dependencies but one runtime — a mixed\n"
            "pair fails every scheduled CodeQL run, invisibly until the next schedule.\n"
            "See #1359 and the grouping in .github/dependabot.yml.",
            file=sys.stderr,
        )
        return 1

    repos = len({repo for _, _, repo, _ in refs})
    print(f"action-pin gate: {len(refs)} references across {repos} repos, all SHA-pinned and consistent.")
    return 0


def self_test() -> int:
    """Validate the checker against a positive case and each negative control.

    A gate's success path proves nothing, so every invariant gets a fixture that
    must make it fire — and the clean fixture must NOT fire, which is what rules
    out a checker that simply flags everything.
    """
    sha_a = "a" * 40
    sha_b = "b" * 40
    sha_c = "c" * 40

    clean = (
        f"      - uses: actions/checkout@{sha_a} # v7.0.0\n"
        f"      - uses: github/codeql-action/init@{sha_b} # v4.37.6\n"
        f"      - uses: github/codeql-action/analyze@{sha_b} # v4.37.6\n"
        f"      - uses: ./.github/actions/local-thing\n"
        f"      - uses: docker://alpine:3.20\n"
    )
    refs = parse_refs(clean, "clean.yml")
    if len(refs) != 3:
        print(f"self-test: expected 3 remote refs (local/docker skipped), got {len(refs)}", file=sys.stderr)
        return 1
    problems = find_problems(refs)
    if problems:
        print(f"self-test: clean fixture reported false positives: {problems}", file=sys.stderr)
        return 1

    # Negative control 1 — the #1359 shape: one repo, two SHAs. Distinct repos
    # pinned to distinct SHAs sit in the same fixture and must NOT be flagged,
    # so a checker that flags any SHA difference fails here rather than passing.
    diverged = (
        f"      - uses: github/codeql-action/init@{sha_b} # v4.37.3\n"
        f"      - uses: github/codeql-action/analyze@{sha_c} # v4.37.4\n"
        f"      - uses: actions/checkout@{sha_a} # v7.0.0\n"
    )
    problems = find_problems(parse_refs(diverged, "diverged.yml"))
    if len(problems) != 1 or "github/codeql-action: 2 different SHAs" not in problems[0]:
        print(f"self-test: divergence not detected as expected; got {problems}", file=sys.stderr)
        return 1

    # Negative control 2 — a floating tag.
    floating = f"      - uses: actions/checkout@v4\n      - uses: actions/cache@{sha_a}\n"
    problems = find_problems(parse_refs(floating, "floating.yml"))
    if len(problems) != 1 or "not pinned to a 40-hex commit SHA" not in problems[0]:
        print(f"self-test: floating tag not detected as expected; got {problems}", file=sys.stderr)
        return 1

    print("self-test: passed (clean fixture + divergence control + floating-tag control).")
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
