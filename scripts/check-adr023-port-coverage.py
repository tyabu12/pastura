#!/usr/bin/env python3
"""Enforce ADR-023 §4's port-disposition coverage invariant (#1191).

ADR-023 §4 declares that every Swift file under `Pastura/Pastura/Engine/**` and
`Pastura/Pastura/LLM/**` carries exactly one disposition (PORT / STAY / REPLACED
/ FOLDED / SPLIT, exclusions as an explicit EXEMPT). A SPLIT row is a one-to-many
port: the Swift file's content lands in more than one Kotlin file, at least one
of which does not carry the Swift file's name (ADR-023 §13 amendment
2026-08-22). Before this gate the invariant was a prose assertion nobody ran —
which is exactly how §4 went stale within hours of being written (the
2026-07-08 batch put four run-path mechanisms outside the scope split and
nothing noticed). This script is the enforcement:
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

# A disposition that requires naming the Kotlin symbol(s) it went to (ADR-023
# §4: "REPLACED and FOLDED exist because Kotlin does not preserve Swift's file
# boundaries"; §13 adds SPLIT for the inverse, one-to-many, shape). PORT/STAY
# carry no target (blank); EXEMPT may carry a note. A SPLIT target is a
# comma-separated list of repo-relative `shared/**/*.kt` paths — every Kotlin
# file the Swift content has landed in, verified against the tracked tree
# (unlike REPLACED/FOLDED targets, which stay free text — ADR-023 §13).
VALID_DISPOSITIONS = {"PORT", "STAY", "REPLACED", "FOLDED", "SPLIT", "EXEMPT"}
TARGET_REQUIRED = {"REPLACED", "FOLDED", "SPLIT"}
TARGET_FORBIDDEN = {"PORT", "STAY"}

# Floor guard: the two directories hold ~87 Swift files. If enumeration returns
# far fewer, git or the path globs drifted — refuse to pass silently rather than
# green-light an empty tree (mirrors check-scenario-format-coverage.py's guard).
MIN_TRACKED_FILES = 50

# Floor guard for SPLIT-target verification: `git ls-files -- shared | grep -c
# '\.kt$'` measured 160 tracked `.kt` files on 2026-08-22. 80 keeps ~2x headroom
# (mirrors MIN_TRACKED_FILES's ~57% ratio above) while still catching a git or
# path-glob regression that would otherwise silently pass every SPLIT target.
MIN_TRACKED_SHARED_KT = 80


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


def tracked_shared_kt_files() -> set[str]:
    """The tracked `.kt` files under `shared/`, via `git ls-files`.

    Filtered to `.kt`: a SPLIT target is always a Kotlin file (ADR-023 §13), so
    a tracked non-`.kt` path under `shared/` (e.g. the ledger TSV itself) is
    never a valid target and excluding it here keeps membership checks tight.
    """
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", "shared"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    return {
        path
        for path in result.stdout.split("\0")
        if path.endswith(".kt")
    }


def _split_target_errors(path: str, target: str, shared_files: set[str]) -> list[str]:
    """Validate a SPLIT row's column-3 target list against ADR-023 §13.

    `target` is a comma-separated list of repo-relative paths; whitespace
    around commas is tolerated. Each entry must lie under `shared/`, end in
    `.kt`, and be a tracked file; an empty entry (e.g. a trailing comma) or a
    duplicate entry within the row is an error. Returns one error string per
    violation, each naming the row's Swift path and the offending entry.
    """
    errors: list[str] = []
    seen_entries: set[str] = set()
    for raw_entry in target.split(","):
        entry = raw_entry.strip()
        if not entry:
            errors.append(
                f"{path}: SPLIT target has an empty entry (check for a stray "
                f"comma in {target!r})"
            )
            continue
        if entry in seen_entries:
            errors.append(f"{path}: SPLIT target entry {entry!r} is duplicated")
            continue
        seen_entries.add(entry)
        if not entry.startswith("shared/"):
            errors.append(f"{path}: SPLIT target entry {entry!r} must lie under shared/")
        elif not entry.endswith(".kt"):
            errors.append(f"{path}: SPLIT target entry {entry!r} must end in .kt")
        elif entry not in shared_files:
            errors.append(
                f"{path}: SPLIT target entry {entry!r} is not a tracked file "
                "under shared/"
            )
    return errors


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


def evaluate(
    files: set[str],
    entries: list[tuple[str, str, str]],
    shared_files: set[str],
) -> list[str]:
    """Pure invariant check. Returns a list of error strings ([] == passes).

    `shared_files` is the tracked-`shared/**/*.kt` set a SPLIT row's targets
    are verified against; REPLACED/FOLDED targets stay free text (ADR-023
    §13) and never consult it. Kept free of I/O so `--self-test` can drive it
    with synthetic inputs.
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
        if disposition == "SPLIT" and target:
            errors.extend(_split_target_errors(path, target, shared_files))

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

    try:
        shared_files = tracked_shared_kt_files()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"coverage gate: `git ls-files -- shared` failed: {exc}", file=sys.stderr)
        return 1

    if len(shared_files) < MIN_TRACKED_SHARED_KT:
        print(
            f"coverage gate: enumerated only {len(shared_files)} tracked .kt "
            "file(s) under shared/ — git or the path globs drifted; refusing "
            "to pass silently.",
            file=sys.stderr,
        )
        return 1

    if not LEDGER.exists():
        print(f"coverage gate: ledger not found at {LEDGER.relative_to(REPO)}", file=sys.stderr)
        return 1

    errors = evaluate(files, parse_ledger(LEDGER.read_text(encoding="utf-8")), shared_files)
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
    shared_files = {"shared/engine/One.kt", "shared/engine/Two.kt"}

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
    ok &= expect("complete manifest", evaluate(files, complete, shared_files), True)
    # Direction (a): a tracked file with no entry.
    ok &= expect(
        "unclassified file",
        evaluate(files, [e for e in complete if e[0] != "d.swift"], shared_files),
        False,
    )
    # Direction (b): an entry pointing at a file that does not exist.
    ok &= expect(
        "dangling entry",
        evaluate(files, complete + [("ghost.swift", "PORT", "")], shared_files),
        False,
    )
    # Per-row: invalid disposition.
    ok &= expect(
        "invalid disposition",
        evaluate(files, [("a.swift", "MOVE", "")] + complete[1:], shared_files),
        False,
    )
    # Per-row: REPLACED/FOLDED without a Kotlin target.
    ok &= expect(
        "REPLACED missing target",
        evaluate(
            files, complete[:2] + [("c.swift", "REPLACED", "")] + complete[3:], shared_files
        ),
        False,
    )
    # Per-row: PORT/STAY carrying a stray target.
    ok &= expect(
        "PORT with stray target",
        evaluate(files, [("a.swift", "PORT", "Oops.kt")] + complete[1:], shared_files),
        False,
    )
    # Per-row: duplicate entry.
    ok &= expect(
        "duplicate entry",
        evaluate(files, complete + [("a.swift", "STAY", "")], shared_files),
        False,
    )
    # SPLIT: one valid target passes.
    ok &= expect(
        "SPLIT single valid target",
        evaluate(
            files,
            complete[:3] + [("d.swift", "SPLIT", "shared/engine/One.kt")],
            shared_files,
        ),
        True,
    )
    # SPLIT: two comma-separated valid targets, space after the comma, passes.
    ok &= expect(
        "SPLIT two valid targets",
        evaluate(
            files,
            complete[:3]
            + [("d.swift", "SPLIT", "shared/engine/One.kt, shared/engine/Two.kt")],
            shared_files,
        ),
        True,
    )
    # SPLIT: no target fails (TARGET_REQUIRED).
    ok &= expect(
        "SPLIT missing target",
        evaluate(files, complete[:3] + [("d.swift", "SPLIT", "")], shared_files),
        False,
    )
    # SPLIT: target names an untracked path.
    ok &= expect(
        "SPLIT untracked target",
        evaluate(
            files,
            complete[:3] + [("d.swift", "SPLIT", "shared/engine/Ghost.kt")],
            shared_files,
        ),
        False,
    )
    # SPLIT: target names a tracked path outside shared/.
    ok &= expect(
        "SPLIT target outside shared/",
        evaluate(
            files,
            complete[:3] + [("d.swift", "SPLIT", "Pastura/Pastura/Engine/Other.kt")],
            shared_files | {"Pastura/Pastura/Engine/Other.kt"},
        ),
        False,
    )
    # SPLIT: target names a tracked non-.kt path.
    ok &= expect(
        "SPLIT non-.kt target",
        evaluate(
            files,
            complete[:3] + [("d.swift", "SPLIT", "shared/adr-023-port-ledger.tsv")],
            shared_files | {"shared/adr-023-port-ledger.tsv"},
        ),
        False,
    )
    # SPLIT: trailing comma / empty entry.
    ok &= expect(
        "SPLIT trailing comma",
        evaluate(
            files,
            complete[:3] + [("d.swift", "SPLIT", "shared/engine/One.kt,")],
            shared_files,
        ),
        False,
    )
    # SPLIT: duplicate entry within the row.
    ok &= expect(
        "SPLIT duplicate entry",
        evaluate(
            files,
            complete[:3]
            + [("d.swift", "SPLIT", "shared/engine/One.kt,shared/engine/One.kt")],
            shared_files,
        ),
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
