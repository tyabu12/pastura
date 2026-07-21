#!/usr/bin/env python3
"""Enforce ADR-023 §4's port-disposition coverage invariant (#1191).

ADR-023 §4 declares that every Swift file under `Pastura/Pastura/Engine/**` and
`Pastura/Pastura/LLM/**` carries exactly one disposition (PORT / STAY / REPLACED
/ FOLDED, exclusions as an explicit EXEMPT). Before this gate the invariant was a
prose assertion nobody ran — which is exactly how §4 went stale within hours of
being written (the 2026-07-08 batch put four run-path mechanisms outside the
scope split and nothing noticed). This script is the enforcement:
`shared/adr-023-port-ledger.tsv` is the manifest, and this gate cross-checks it
against the tracked tree in BOTH directions —

  (a) every tracked Swift file has a ledger entry   (no unclassified / UNDECIDED file)
  (b) every ledger entry points at a tracked file   (no dangling entry)

which together reduce to: the ledger's path set EQUALS the tracked Swift-file set.
One direction alone rots — (a) misses a deleted file whose row lingers, (b) misses
a newly-added file with no row.

Tracked-only scope (NOT a worktree walk). Per `.claude/rules/ci-workflows.md`
§ "Gate scripts": a gate asserting a repository invariant must read tracked files
(`git ls-files`), never `os.walk` the worktree — otherwise it picks up untracked
or gitignored `.swift` on a developer machine while CI (a clean checkout) sees
only tracked files, the classic CI-green/local-red split. This also matches the
pre-commit sub-gate, which self-gates on `git diff --cached` (the index).

The scope is Swift because the port is: `LLM/SafeSampler/{.h,.mm}` are the only
non-Swift files and belong to the llama.cpp backend that STAYs wholesale, so they
are out of the ledger entirely rather than EXEMPT (ADR-023 §4).

Usage:
    check-adr023-port-coverage.py [--check]   # default: gate the real ledger + tree
    check-adr023-port-coverage.py --self-test # validate the checker itself
"""
from __future__ import annotations

import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER = REPO / "shared" / "adr-023-port-ledger.tsv"
SCOPE_DIRS = ["Pastura/Pastura/Engine", "Pastura/Pastura/LLM"]

# A disposition that requires naming the Kotlin symbol it went to (ADR-023 §4:
# "REPLACED and FOLDED exist because Kotlin does not preserve Swift's file
# boundaries"). PORT/STAY carry no target (blank); EXEMPT may carry a note.
VALID_DISPOSITIONS = {"PORT", "STAY", "REPLACED", "FOLDED", "EXEMPT"}
TARGET_REQUIRED = {"REPLACED", "FOLDED"}
TARGET_FORBIDDEN = {"PORT", "STAY"}

# Floor guard: the two directories hold ~87 Swift files. If enumeration returns
# far fewer, git or the path globs drifted — refuse to pass silently rather than
# green-light an empty tree (mirrors check-scenario-format-coverage.py's guard).
MIN_TRACKED_FILES = 50


def tracked_swift_files() -> set[str]:
    """The tracked `.swift` files under the two scope dirs, via `git ls-files`."""
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", *SCOPE_DIRS],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    return {
        path
        for path in result.stdout.split("\0")
        if path.endswith(".swift")
    }


def parse_ledger(text: str) -> list[tuple[str, str, str]]:
    """Parse the ledger TSV -> [(swift_path, disposition, kotlin_target)].

    Skips `#` comment lines, blank lines, and the `swift_path\t...` header row.
    A row is 2 or 3 tab-separated fields; a missing third field is "".
    """
    rows: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if fields[0] == "swift_path":  # header
            continue
        path = fields[0].strip()
        disposition = fields[1].strip() if len(fields) > 1 else ""
        target = fields[2].strip() if len(fields) > 2 else ""
        rows.append((path, disposition, target))
    return rows


def evaluate(files: set[str], entries: list[tuple[str, str, str]]) -> list[str]:
    """Pure invariant check. Returns a list of error strings ([] == passes).

    Kept free of I/O so `--self-test` can drive it with synthetic inputs.
    """
    errors: list[str] = []

    # Per-row validation + duplicate detection.
    seen: set[str] = set()
    for path, disposition, target in entries:
        if path in seen:
            errors.append(f"duplicate ledger entry for {path}")
        seen.add(path)
        if disposition not in VALID_DISPOSITIONS:
            errors.append(
                f"{path}: invalid disposition {disposition!r} "
                f"(expected one of {', '.join(sorted(VALID_DISPOSITIONS))})"
            )
            continue
        if disposition in TARGET_REQUIRED and not target:
            errors.append(
                f"{path}: {disposition} entry must name its Kotlin target in "
                "column 3 (ADR-023 §4)"
            )
        if disposition in TARGET_FORBIDDEN and target:
            errors.append(
                f"{path}: {disposition} entry must not carry a Kotlin target "
                f"(got {target!r})"
            )

    ledger_paths = seen

    # Direction (a): every tracked Swift file has an entry.
    for path in sorted(files - ledger_paths):
        errors.append(
            f"{path}: tracked Swift file has no ledger entry (UNDECIDED — assign "
            "a disposition in shared/adr-023-port-ledger.tsv)"
        )

    # Direction (b): every entry points at a tracked file.
    for path in sorted(ledger_paths - files):
        errors.append(
            f"{path}: ledger entry points at a file not tracked under "
            f"{' / '.join(SCOPE_DIRS)} (dangling — remove it or fix the path)"
        )

    return errors


def check() -> int:
    try:
        files = tracked_swift_files()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"coverage gate: `git ls-files` failed: {exc}", file=sys.stderr)
        return 1

    if len(files) < MIN_TRACKED_FILES:
        print(
            f"coverage gate: enumerated only {len(files)} tracked Swift file(s) "
            f"under {' / '.join(SCOPE_DIRS)} — git or the path globs drifted; "
            "refusing to pass silently.",
            file=sys.stderr,
        )
        return 1

    if not LEDGER.exists():
        print(f"coverage gate: ledger not found at {LEDGER.relative_to(REPO)}", file=sys.stderr)
        return 1

    errors = evaluate(files, parse_ledger(LEDGER.read_text(encoding="utf-8")))
    if errors:
        for err in errors:
            print(f"coverage gate: {err}", file=sys.stderr)
        print(
            f"\nADR-023 §4 requires every Swift file under {' / '.join(SCOPE_DIRS)} "
            "to carry exactly one disposition in shared/adr-023-port-ledger.tsv, "
            "checked in both directions. Reconcile the ledger and re-run.",
            file=sys.stderr,
        )
        return 1

    print(
        f"coverage gate: {len(files)} tracked Swift files ↔ ledger reconcile "
        "(both directions, all dispositions valid)."
    )
    return 0


def self_test() -> int:
    """Validate the checker on synthetic inputs: a complete manifest passes, and
    every failure mode the invariant names is detected — both bidirectional
    directions plus the per-row rules."""
    files = {"a.swift", "b.swift", "c.swift", "d.swift"}
    complete = [
        ("a.swift", "PORT", ""),
        ("b.swift", "STAY", ""),
        ("c.swift", "REPLACED", "Foo.kt"),
        ("d.swift", "FOLDED", "Bar.kt"),
    ]

    def expect(label: str, got: list[str], want_ok: bool) -> bool:
        ok = (len(got) == 0)
        if ok != want_ok:
            print(
                f"self-test: {label}: expected {'pass' if want_ok else 'failure'}, "
                f"got errors={got}",
                file=sys.stderr,
            )
            return False
        return True

    ok = True
    # Positive: the complete manifest reconciles.
    ok &= expect("complete manifest", evaluate(files, complete), True)
    # Direction (a): a tracked file with no entry.
    ok &= expect(
        "unclassified file",
        evaluate(files, [e for e in complete if e[0] != "d.swift"]),
        False,
    )
    # Direction (b): an entry pointing at a file that does not exist.
    ok &= expect(
        "dangling entry",
        evaluate(files, complete + [("ghost.swift", "PORT", "")]),
        False,
    )
    # Per-row: invalid disposition.
    ok &= expect(
        "invalid disposition",
        evaluate(files, [("a.swift", "MOVE", "")] + complete[1:]),
        False,
    )
    # Per-row: REPLACED/FOLDED without a Kotlin target.
    ok &= expect(
        "REPLACED missing target",
        evaluate(files, complete[:2] + [("c.swift", "REPLACED", "")] + complete[3:]),
        False,
    )
    # Per-row: PORT/STAY carrying a stray target.
    ok &= expect(
        "PORT with stray target",
        evaluate(files, [("a.swift", "PORT", "Oops.kt")] + complete[1:]),
        False,
    )
    # Per-row: duplicate entry.
    ok &= expect(
        "duplicate entry",
        evaluate(files, complete + [("a.swift", "STAY", "")]),
        False,
    )

    if not ok:
        return 1
    print("self-test: passed (positive manifest + both directions + per-row rules).")
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
