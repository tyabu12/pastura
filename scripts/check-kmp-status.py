#!/usr/bin/env python3
"""Keep the KMP migration status board's Wave B checklist honest (#1231).

`docs/kmp-migration-status.md` is a hand-maintained at-a-glance progress view.
Its one section whose accuracy is *filesystem-derivable* — the Wave B phase-handler
checklist — is the one most likely to drift silently (a `[x]` ticked before the
port lands, or a fresh port whose row nobody flips). This gate makes that section
mechanical:

  a ported handler == a Kotlin file at
  `shared/engine/src/commonMain/kotlin/com/pastura/engine/Phases/<Name>.kt`

and enforces, bidirectionally, that the board's `[x]` marks match reality.

Single upstream, not a parallel list. The *set* of handlers the board must list
is derived from `shared/adr-023-port-ledger.tsv` (its
`Pastura/Pastura/Engine/Phases/*Handler.swift` rows), NOT from a second
hand-maintained enumeration. The ledger's own gate
(`check-adr023-port-coverage.py`) independently keeps that set == the tracked
Swift tree, so this gate does not re-police Swift-side completeness — the two are
complementary: the ledger tracks *disposition*, this board tracks *progress*.

Checks (all bidirectional — a status board's failure mode is a false positive):
  1. the board lists EXACTLY the ledger's handler set   (no missing row, no orphan)
  2. every `[x]` handler has a ported `.kt`              (no premature/false tick)
  3. every ported `.kt` handler is `[x]`                 (no un-flipped fresh port)
  4. every ported `.kt` maps to a ledger handler         (no stray Kotlin file)
Handler names are matched whole (SpeakAll vs SpeakEach are distinct).

Tracked-only scope (NOT a worktree walk), per `.claude/rules/ci-workflows.md`
§ "Gate scripts": the ported `.kt` set comes from `git ls-files`, so a clean CI
checkout and a developer machine see the same tree (an untracked/gitignored `.kt`
never counts).

Usage:
    check-kmp-status.py [--check]   # default: gate the real board + ledger + tree
    check-kmp-status.py --self-test # validate the checker itself
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
BOARD = REPO / "docs" / "kmp-migration-status.md"
LEDGER = REPO / "shared" / "adr-023-port-ledger.tsv"
KT_PHASES_DIR = "shared/engine/src/commonMain/kotlin/com/pastura/engine/Phases"

# A ledger row whose swift_path is a phase handler. The board's Wave B section
# lists exactly these (by handler name = the basename without `.swift`).
LEDGER_HANDLER_RE = re.compile(
    r"^Pastura/Pastura/Engine/Phases/(\w+Handler)\.swift\t"
)

# The Wave B checklist is fenced by HTML-comment markers so parsing is exact and
# other checkbox-shaped lines in the doc are never mistaken for handler rows.
WAVE_B_START = "<!-- kmp-status:wave-b:start -->"
WAVE_B_END = "<!-- kmp-status:wave-b:end -->"
# `- [x] AssignHandler — #1226`  /  `- [ ] ChooseHandler`
CHECKLIST_ROW_RE = re.compile(r"^- \[([ xX])\]\s+(\w+Handler)\b")

# Floor guard: there are ~14 handlers. If the ledger yields far fewer, its format
# or the regex drifted — refuse to pass silently (mirrors the sibling gates).
MIN_HANDLERS = 10


def ledger_handlers(text: str) -> set[str]:
    """Handler names (basename w/o `.swift`) from the ledger's Phases rows."""
    return {m.group(1) for m in (LEDGER_HANDLER_RE.match(line) for line in text.splitlines()) if m}


def ported_handlers() -> set[str]:
    """Handler names with a tracked `.kt` under the commonMain Phases dir."""
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", KT_PHASES_DIR],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    )
    names: set[str] = set()
    for path in result.stdout.split("\0"):
        if path.endswith(".kt"):
            names.add(path.rsplit("/", 1)[-1][: -len(".kt")])
    return names


def parse_board(text: str) -> dict[str, bool]:
    """Wave B checklist -> {handler_name: is_checked}. Raises on a malformed fence."""
    lines = text.splitlines()
    try:
        start = next(i for i, ln in enumerate(lines) if ln.strip() == WAVE_B_START)
        end = next(i for i, ln in enumerate(lines) if ln.strip() == WAVE_B_END)
    except StopIteration:
        raise ValueError(
            f"board is missing the Wave B fence "
            f"({WAVE_B_START} … {WAVE_B_END})"
        )
    if end <= start:
        raise ValueError("board Wave B end marker precedes its start marker")
    rows: dict[str, bool] = {}
    for ln in lines[start + 1 : end]:
        m = CHECKLIST_ROW_RE.match(ln)
        if m:
            rows[m.group(2)] = m.group(1).lower() == "x"
    return rows


def evaluate(handlers: set[str], ported: set[str], board: dict[str, bool]) -> list[str]:
    """Pure invariant check. Returns a list of error strings ([] == passes).

    Kept free of I/O so `--self-test` can drive it with synthetic inputs.
    """
    errors: list[str] = []
    board_names = set(board)

    # (1) the board lists exactly the ledger's handler set.
    for name in sorted(handlers - board_names):
        errors.append(f"{name}: handler in the ledger has no Wave B checklist row (add it)")
    for name in sorted(board_names - handlers):
        errors.append(
            f"{name}: Wave B checklist row names no ledger handler "
            "(orphan/stale — a rename or fold? remove or fix it)"
        )

    # (4) every ported .kt maps to a ledger handler.
    for name in sorted(ported - handlers):
        errors.append(
            f"{name}: ported .kt under {KT_PHASES_DIR} maps to no ledger handler "
            "(stray Kotlin file or a ledger gap)"
        )

    # (2)+(3) each in-set handler's checkbox matches .kt existence, both directions.
    for name in sorted(handlers & board_names):
        is_ported = name in ported
        if board[name] and not is_ported:
            errors.append(
                f"{name}: marked [x] but no ported .kt exists at "
                f"{KT_PHASES_DIR}/{name}.kt (false tick)"
            )
        elif is_ported and not board[name]:
            errors.append(
                f"{name}: a ported .kt exists but the row is [ ] (flip it to [x])"
            )
    return errors


def check() -> int:
    if not BOARD.exists():
        print(f"kmp-status gate: board not found at {BOARD.relative_to(REPO)}", file=sys.stderr)
        return 1
    if not LEDGER.exists():
        print(f"kmp-status gate: ledger not found at {LEDGER.relative_to(REPO)}", file=sys.stderr)
        return 1

    handlers = ledger_handlers(LEDGER.read_text(encoding="utf-8"))
    if len(handlers) < MIN_HANDLERS:
        print(
            f"kmp-status gate: only {len(handlers)} handler(s) parsed from the "
            "ledger — its format or the row regex drifted; refusing to pass silently.",
            file=sys.stderr,
        )
        return 1

    try:
        ported = ported_handlers()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"kmp-status gate: `git ls-files` failed: {exc}", file=sys.stderr)
        return 1

    try:
        board = parse_board(BOARD.read_text(encoding="utf-8"))
    except ValueError as exc:
        print(f"kmp-status gate: {exc}", file=sys.stderr)
        return 1

    errors = evaluate(handlers, ported, board)
    if errors:
        for err in errors:
            print(f"kmp-status gate: {err}", file=sys.stderr)
        print(
            "\nThe Wave B checklist in docs/kmp-migration-status.md must list exactly "
            "the ledger's phase handlers, each [x] iff a ported .kt exists. Reconcile "
            "the board and re-run.",
            file=sys.stderr,
        )
        return 1

    print(
        f"kmp-status gate: {len(handlers)} handlers, {len(ported)} ported ↔ board "
        "reconcile (both directions)."
    )
    return 0


def self_test() -> int:
    """Validate the checker on synthetic inputs: a consistent board passes, and
    every failure mode the invariant names is detected."""
    handlers = {"AssignHandler", "ChooseHandler", "SpeakAllHandler", "SpeakEachHandler"}
    ported = {"AssignHandler", "SpeakAllHandler"}
    good = {
        "AssignHandler": True,
        "ChooseHandler": False,
        "SpeakAllHandler": True,
        "SpeakEachHandler": False,
    }

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
    # Positive: a fully consistent board.
    ok &= expect("consistent board", evaluate(handlers, ported, good), True)
    # (2) false tick: [x] with no ported .kt.
    false_tick = dict(good, ChooseHandler=True)
    ok &= expect("false tick", evaluate(handlers, ported, false_tick), False)
    # (3) un-flipped fresh port: ported but row still [ ].
    unflipped = dict(good, SpeakAllHandler=False)
    ok &= expect("un-flipped port", evaluate(handlers, ported, unflipped), False)
    # (1a) missing row: a ledger handler absent from the board.
    missing = {k: v for k, v in good.items() if k != "SpeakEachHandler"}
    ok &= expect("missing row", evaluate(handlers, ported, missing), False)
    # (1b) orphan row: a board row naming no ledger handler.
    orphan = dict(good, GhostHandler=False)
    ok &= expect("orphan row", evaluate(handlers, ported, orphan), False)
    # (4) stray .kt: a ported handler outside the ledger set.
    ok &= expect(
        "stray ported .kt",
        evaluate(handlers, ported | {"StrayHandler"}, good),
        False,
    )
    # Whole-name matching: SpeakAll ported must not satisfy SpeakEach's row.
    ok &= expect("consistent (whole-name)", evaluate(handlers, ported, good), True)

    if not ok:
        return 1
    print("self-test: passed (positive board + both directions + orphan/stray/false-tick).")
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
