#!/usr/bin/env python3
"""Tier 2 i18n leak audit for Pastura (Issue #292).

Surfaces Swift string literals that *could* be user-facing but are not yet
wrapped in ``String(localized:)`` — the class of leak that Tier 1's
SwiftLint rule (``unwrapped_user_facing_string`` in ``.swiftlint.yml``)
cannot catch because the leak shape varies semantically (helper-returning
``String`` displayed via ``Text(_:)``, computed properties returning raw
literals, etc.).

Pipeline:

1. Find every ``.swift`` under ``Pastura/Pastura/``, excluding ``Engine/``
   (ADR-010 §4 — Engine emits ``scenario.language``-driven strings, not
   ``Bundle.main`` localizations).
2. Invoke ``xcrun xcstringstool extract --modern-localizable-strings
   --all-potential-swift-keys`` against the batch. Apple's ``stringsdata``
   output groups keys into a ``Localizable`` table (already wrapped via
   ``String(localized:)``) and a ``__PotentialKeys`` table (every other
   string literal Apple's parser thinks *might* be a key). The combined
   flag set means ``__PotentialKeys`` already excludes wrapped keys, so no
   diff against ``Localizable.xcstrings`` is needed.
3. Apply syntactic noise filters (empty / short lowercase identifier /
   dot-notation SF Symbol or accessibility id / URL or file path /
   format-specifier-only / non-letter) to drop the ~85% noise floor
   measured against PR #288's audit (1235 unique potential keys → ~10–30
   true leaks).
4. Print remaining candidates as ``file:line  'key'`` for reviewer triage.

Empirically the filters keep ``Rounds: %arg`` (real leak shape) while
dropping ``minus.circle.fill`` (SF Symbol), ``string`` (type identifier),
and ``''`` (empty literals from runtime concatenation). They are NOT a
hard guarantee — extension is expected as new noise patterns surface; see
``docs/i18n/leak-detection.md`` for the maintenance protocol.

In addition to filename-suffix exclusion (``+Previews.swift``), inline
``#Preview`` macro blocks at file scope are skipped via column-0 brace
matching (see ``compute_preview_block_lines``). The audit relies on the
project-wide convention that ``#Preview`` blocks live at column 0 — all
current Pastura usage matches. Blocks at non-zero indent (inside ``#if
DEBUG`` or nested types) are NOT recognized and surface their bodies as
candidates. PR review enforces the file-scope convention (no SwiftLint
rule covers this today).

The filter pipeline distinguishes two filter shapes:

* **Key-text filters** (``NOISE_FILTERS``) — ``Callable[[str], bool]``
  predicates evaluated against the literal text. Extend by adding a row
  to ``NOISE_FILTERS`` and a TP+FP fixture pair to ``_self_test``.
* **Location-based filters** (``apply_preview_filter`` etc.) — pre-pass
  before key-text filtering. Operate on the candidate dict's ``file`` /
  ``line``. Extend by adding a sibling pass in ``main`` and dedicated
  self-test fixtures keyed on source text.

Run ``--self-test`` to exercise each filter against in-memory fixtures
before invoking on the full tree. Unlike ``check_localization_coverage.py``
this script is **NOT** wired into CI (per Issue #292 AC: ratio of true
positives to noise is too low for a hard gate). It is a developer audit
tool — invoke locally when adding a new ViewModel, helper that returns
display-bound ``String``, or feature surface that introduces ``Text(_:)``
of computed values.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Callable, Iterable

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Pastura" / "Pastura"

# ADR-010 §4 — Engine layer reads ``scenario.language`` directly, not
# ``Bundle.main.preferredLocalizations``; its hardcoded strings are
# intentionally excluded from ``Localizable.xcstrings``.
EXCLUDED_PATH_PREFIXES: tuple[Path, ...] = (
    SOURCE_DIR / "Engine",
)

# Filename-suffix exclusions. SwiftUI ``+Previews.swift`` files contain
# ``#Preview`` macro bodies — preview names and dev-only fixture data that
# never ships at runtime. Excluding them by suffix follows Pastura's
# existing convention (``PromoCard+Previews.swift``, etc.) and avoids
# baking a per-file curated allow-list.
EXCLUDED_FILENAME_SUFFIXES: tuple[str, ...] = (
    "+Previews.swift",
)

# ---------------------------------------------------------------------------
# Noise filters
# ---------------------------------------------------------------------------
# Each filter is purely syntactic. We deliberately do NOT path-exclude the
# audit-list files (``BackgroundSimulationManager``, ``ResultMarkdownExporter``,
# ``PromoCard``, ``DLCompleteOverlay``, ``ImportViewModel``) because a future
# leak introduced into those files should still surface — PR #299's audit
# verified the *current* literals only.

_EMPTY_RE = re.compile(r"^\s*$")
# Short lowercase identifier (≤ 8 chars, lowercase/digits/underscore only).
# Catches Swift type-name literals leaking into __PotentialKeys ("string",
# "bool", "int", "id", "arg") without swallowing real button labels like
# "OK" / "Cancel" (uppercase) or longer English words like "Loading" /
# "Continue" (≥ 9 chars). 8-char ceiling is a hand-tuned heuristic — see
# docs/i18n/leak-detection.md for the trade-off discussion.
_IDENTIFIER_RE = re.compile(r"^[a-z][a-z0-9_]{0,7}$")
# SF Symbol (``minus.circle.fill``) or accessibility identifier
# (``home.scenario.row``): all-lowercase with at least one dot, at least one
# letter. Pure version strings ("1.0.0") are also dropped, which is fine —
# they would not need ``String(localized:)`` either way.
_DOT_NOTATION_RE = re.compile(r"^[a-z0-9_-]*[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)+$")
# URL scheme (``https://``, ``file:///``), absolute path (``/Users/...``),
# or home-relative path (``~/Library``).
_URL_OR_PATH_RE = re.compile(r"(?:^[/~]|://)")
# Format-specifier-only key (``%arg``, ``%@``, ``%d``, ``%lld``).
# Real user-facing format strings have a prefix or suffix and won't match.
# ``@`` is included for ``%@`` (Objective-C-bridged object substitution).
_FORMAT_ONLY_RE = re.compile(r"^\s*%[\w@]+\s*$")

NOISE_FILTERS: tuple[tuple[str, Callable[[str], bool], str], ...] = (
    ("empty", lambda k: bool(_EMPTY_RE.match(k)), "empty / whitespace-only"),
    (
        "identifier",
        lambda k: bool(_IDENTIFIER_RE.match(k)),
        "short lowercase identifier (≤8 chars)",
    ),
    (
        "dot-notation",
        lambda k: bool(_DOT_NOTATION_RE.match(k)),
        "SF Symbol or accessibility identifier (lowercase + dot)",
    ),
    (
        "url-or-path",
        lambda k: bool(_URL_OR_PATH_RE.search(k)),
        "URL scheme or file path",
    ),
    (
        "format-only",
        lambda k: bool(_FORMAT_ONLY_RE.match(k)),
        "format specifier with no surrounding text",
    ),
    (
        "no-letter",
        # Unicode-aware: keep CJK / Cyrillic / Greek strings (Japanese
        # marketing copy in PromoCard / DLCompleteOverlay shows up as
        # candidates and the reviewer triages). ``str.isalpha()`` recognizes
        # any Unicode letter, not just ``[A-Za-z]``.
        lambda k: not any(c.isalpha() for c in k),
        "punctuation / digits only (no letter in any script)",
    ),
)


def classify_key(key: str) -> str | None:
    """Returns the filter name that drops the key, or ``None`` if kept."""
    for name, predicate, _ in NOISE_FILTERS:
        if predicate(key):
            return name
    return None


# ---------------------------------------------------------------------------
# Location-based pre-filter — #Preview macro block-skip
# ---------------------------------------------------------------------------
# Pastura convention: `#Preview` macros live at file scope (column 0). The
# closing `}` is therefore also at column 0, and the body's nested braces
# (closures, struct literals) are at non-zero indent under swift-format.
# Finding the first column-0 `}` after a column-0 `#Preview` line is
# sufficient to bound the block without a real tokenizer — failing open
# on stray column-0 `}` (early-terminates the block, leaves later content
# visible) rather than swallowing real leaks. See
# `docs/i18n/leak-detection.md` § "Explicitly-deferred or permanent
# carve-outs" for the file-scope-only contract.

_PREVIEW_START_RE = re.compile(r"^#Preview\b")
_PREVIEW_FILTER_NAME = "preview-macro"
_PREVIEW_FILTER_DESCRIPTION = "inside #Preview macro body (file-scope only)"


def compute_preview_block_lines(source: str) -> set[int]:
    """Returns 1-indexed line numbers inside file-scope ``#Preview { ... }`` bodies.

    Includes the ``#Preview`` line itself and the closing ``}`` line.
    """
    lines = source.splitlines()
    skip: set[int] = set()
    i = 0
    while i < len(lines):
        if _PREVIEW_START_RE.match(lines[i]):
            start_idx = i
            end_idx: int | None = None
            # Find the first column-0 closing brace AFTER the #Preview line.
            # No brace-depth tracking needed under Pastura's swift-format
            # convention — see header comment above.
            for j in range(i + 1, len(lines)):
                if lines[j].startswith("}"):
                    end_idx = j
                    break
            if end_idx is None:
                # Unterminated block — bail without over-extending.
                i += 1
                continue
            for k in range(start_idx, end_idx + 1):
                skip.add(k + 1)  # 1-indexed
            i = end_idx + 1
        else:
            i += 1
    return skip


def apply_preview_filter(
    candidates: Iterable[dict],
) -> tuple[list[dict], int]:
    """Drops candidates whose ``(file, line)`` falls inside a ``#Preview`` body.

    Caches the per-file preview-line set so each source is read at most
    once. Returns ``(kept_candidates, dropped_count)``; the caller
    attributes ``dropped_count`` to the ``preview-macro`` row of the
    summary breakdown.
    """
    preview_cache: dict[Path, set[int]] = {}
    kept: list[dict] = []
    dropped = 0
    for cand in candidates:
        path = cand["file"]
        if path not in preview_cache:
            try:
                source = path.read_text()
            except OSError:
                source = ""
            preview_cache[path] = compute_preview_block_lines(source)
        if cand["line"] in preview_cache[path]:
            dropped += 1
        else:
            kept.append(cand)
    return kept, dropped


# ---------------------------------------------------------------------------
# Source discovery
# ---------------------------------------------------------------------------


def is_excluded_path(path: Path) -> bool:
    if any(
        str(path).startswith(str(prefix)) for prefix in EXCLUDED_PATH_PREFIXES
    ):
        return True
    return any(path.name.endswith(suffix) for suffix in EXCLUDED_FILENAME_SUFFIXES)


def find_swift_sources(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*.swift") if not is_excluded_path(p))


# ---------------------------------------------------------------------------
# xcstringstool integration
# ---------------------------------------------------------------------------


def extract_potential_keys(sources: list[Path]) -> list[dict]:
    """Returns a flat list of ``{file, line, column, key}`` dicts."""
    if not sources:
        return []
    with tempfile.TemporaryDirectory() as tmp:
        cmd = [
            "xcrun",
            "xcstringstool",
            "extract",
            "--modern-localizable-strings",
            "--all-potential-swift-keys",
            "--output-directory",
            tmp,
            *[str(s) for s in sources],
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print("error: xcstringstool extract failed", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            sys.exit(2)

        candidates: list[dict] = []
        for sd in Path(tmp).glob("*.stringsdata"):
            with sd.open() as f:
                data = json.load(f)
            source_path = Path(data["source"])
            for entry in data["tables"].get("__PotentialKeys", []):
                loc = entry["location"]
                candidates.append(
                    {
                        "file": source_path,
                        "line": loc["startingLine"],
                        "column": loc["startingColumn"],
                        "key": entry["key"],
                    }
                )
        return candidates


# ---------------------------------------------------------------------------
# Filter application
# ---------------------------------------------------------------------------


def filter_candidates(candidates: Iterable[dict]) -> tuple[list[dict], dict[str, int]]:
    """Returns ``(kept_candidates, dropped_counts_by_filter)``."""
    kept: list[dict] = []
    dropped: dict[str, int] = defaultdict(int)
    for cand in candidates:
        reason = classify_key(cand["key"])
        if reason is None:
            kept.append(cand)
        else:
            dropped[reason] += 1
    return kept, dict(dropped)


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------


def format_kept(kept: list[dict], root: Path) -> str:
    """Sort by file:line and render as ``relpath:line:col  'key'``."""
    lines: list[str] = []
    for cand in sorted(
        kept, key=lambda c: (str(c["file"]), c["line"], c["column"])
    ):
        try:
            rel = cand["file"].relative_to(root)
        except ValueError:
            rel = cand["file"]
        lines.append(
            f"{rel}:{cand['line']}:{cand['column']}  {cand['key']!r}"
        )
    return "\n".join(lines)


def format_summary(kept: list[dict], dropped: dict[str, int]) -> str:
    total_dropped = sum(dropped.values())
    total_in = len(kept) + total_dropped
    parts = [
        f"Scanned {total_in} potential keys; "
        f"{total_dropped} filtered as noise, {len(kept)} for review."
    ]
    if dropped:
        parts.append("Filter breakdown:")
        for name, _, description in NOISE_FILTERS:
            count = dropped.get(name, 0)
            if count:
                parts.append(f"  · {name:<13} {count:>4}  ({description})")
        # Location-based filters live outside NOISE_FILTERS — render after.
        preview_count = dropped.get(_PREVIEW_FILTER_NAME, 0)
        if preview_count:
            parts.append(
                f"  · {_PREVIEW_FILTER_NAME:<13} {preview_count:>4}  "
                f"({_PREVIEW_FILTER_DESCRIPTION})"
            )
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------


def _self_test() -> int:
    """Exercise each filter category with at least one TP + one FP fixture."""
    cases: list[tuple[str, str, str | None]] = [
        # (description, key, expected_filter_name_or_None)
        # ─── empty filter ─────────────────────────────────────────────────
        ("empty TP — empty literal", "", "empty"),
        ("empty TP — whitespace only", "   ", "empty"),
        ("empty FP — single space-padded letter is real", " a ", None),
        # ─── identifier filter ────────────────────────────────────────────
        ("identifier TP — Swift type 'string'", "string", "identifier"),
        ("identifier TP — short lower 'arg'", "arg", "identifier"),
        ("identifier FP — uppercase first 'Cancel' kept", "Cancel", None),
        # 'loading' (7 chars) DOES match the identifier filter; real UI copy
        # is conventionally capitalized ('Loading'), so this is intentional.
        ("identifier FP — capitalized 'Loading' kept", "Loading", None),
        ("identifier FP — 'OK' uppercase kept", "OK", None),
        # ─── dot-notation filter ──────────────────────────────────────────
        ("dot TP — SF Symbol", "minus.circle.fill", "dot-notation"),
        ("dot TP — accessibility id", "home.scenario.row", "dot-notation"),
        (
            "dot FP — sentence with full stops kept",
            "Loading. Please wait.",
            None,
        ),
        ("dot FP — version + suffix kept", "Version 1.0.0 — beta", None),
        # ─── url-or-path filter ───────────────────────────────────────────
        ("path TP — URL scheme", "https://example.com", "url-or-path"),
        ("path TP — absolute path", "/Users/me/Library", "url-or-path"),
        ("path TP — home-relative path", "~/Documents", "url-or-path"),
        ("path FP — sentence containing 'or'", "Loading or saving", None),
        # ─── format-only filter ───────────────────────────────────────────
        ("format TP — bare %arg", "%arg", "format-only"),
        ("format TP — %@ alone", "%@", "format-only"),
        ("format FP — prefixed format kept", "Rounds: %arg", None),
        ("format FP — bilingual format kept", "%arg 個", None),
        # ─── no-letter filter ─────────────────────────────────────────────
        ("no-letter TP — punctuation only", " — : ", "no-letter"),
        ("no-letter TP — digits + dashes", "12-34-56", "no-letter"),
        (
            "no-letter FP — Japanese (CJK has no [A-Za-z] but kept by design)",
            "準備ができました",
            None,
        ),
        ("no-letter FP — short word kept (not filtered here)", "ok", "identifier"),
        # ─── real-leak smoke test ─────────────────────────────────────────
        (
            "smoke — phaseTypeDescription leak (PR #288 d446fd9)",
            "All agents speak simultaneously",
            None,
        ),
        ("smoke — verbatim Japanese marketing", "ダウンロードが中断しました", None),
    ]

    print("Self-test fixtures:")
    failures = 0
    for description, key, expected in cases:
        actual = classify_key(key)
        if actual == expected:
            print(f"  ok  {description!r}: classify_key({key!r}) → {actual!r}")
        else:
            failures += 1
            print(
                f"  FAIL {description!r}: classify_key({key!r}) → {actual!r}, "
                f"expected {expected!r}"
            )

    print(f"Self-test: {len(cases) - failures}/{len(cases)} fixtures behaved as expected")

    # Path-exclusion fixtures — independent of classify_key.
    print("Path-exclusion fixtures:")
    path_cases: list[tuple[str, Path, bool]] = [
        (
            "Engine/ excluded (ADR-010 §4)",
            SOURCE_DIR / "Engine" / "Phases" / "SpeakAllHandler.swift",
            True,
        ),
        (
            "App/ kept",
            SOURCE_DIR / "App" / "HomeViewModel.swift",
            False,
        ),
        (
            "+Previews.swift excluded",
            SOURCE_DIR / "Views" / "ModelDownload" / "PromoCard+Previews.swift",
            True,
        ),
        (
            "non-Previews +Helpers kept",
            SOURCE_DIR / "Views" / "ModelDownload" / "PromoCard+Helpers.swift",
            False,
        ),
    ]
    path_failures = 0
    for description, path, expected in path_cases:
        actual = is_excluded_path(path)
        if actual == expected:
            print(f"  ok  {description!r}: is_excluded_path → {actual}")
        else:
            path_failures += 1
            print(
                f"  FAIL {description!r}: is_excluded_path → {actual}, "
                f"expected {expected}"
            )
    print(
        f"Path-exclusion: {len(path_cases) - path_failures}/{len(path_cases)} "
        "behaved as expected"
    )

    # `#Preview` block-skip fixtures — see leak-detection.md § "Extension
    # protocol — adding filters" for the location-based filter shape.
    print("Preview block-skip fixtures:")
    preview_cases: list[tuple[str, str, set[int]]] = [
        (
            "TP — single-line #Preview with named arg",
            "import SwiftUI\n"  # 1
            '#Preview("name") {\n'  # 2
            '  Text("inside")\n'  # 3
            "}\n"  # 4
            'Text("outside")\n',  # 5
            {2, 3, 4},
        ),
        (
            "TP — no-arg #Preview body still detected",
            "#Preview {\n"  # 1
            "  ContentView()\n"  # 2
            "}\n",  # 3
            {1, 2, 3},
        ),
        (
            "FP — string outside #Preview not classified",
            'Text("kept")\n#Preview { Inline() }\n',  # neither line is between
            # The single-line `#Preview { Inline() }` form has its closing
            # `}` on the same line — no subsequent column-0 `}`, so the
            # block is unterminated and the algorithm bails. Line 1 (the
            # real-leak shape) is therefore unaffected.
            set(),
        ),
        (
            "Edge — nested closure inside body",
            'import SwiftUI\n'  # 1
            '#Preview("name") {\n'  # 2
            "  ForEach(items) { item in\n"  # 3
            "    Text(item.name)\n"  # 4
            "  }\n"  # 5  (nested `}` at non-zero indent)
            "}\n",  # 6  (column-0 close)
            {2, 3, 4, 5, 6},
        ),
        (
            "Edge — #Preview with traits arg",
            '#Preview("name", traits: .sizeThatFits) {\n'  # 1
            '  Text("inside")\n'  # 2
            "}\n",  # 3
            {1, 2, 3},
        ),
        (
            "Edge — multi-line opening (#Preview line and { on separate lines)",
            "#Preview(\n"  # 1
            '  "long arg list"\n'  # 2
            ") {\n"  # 3
            '  Text("inside")\n'  # 4
            "}\n",  # 5
            {1, 2, 3, 4, 5},
        ),
        (
            "Edge — unterminated #Preview bails (no column-0 close)",
            '#Preview("oops") {\n'
            '  Text("inside")\n'
            # No closing column-0 `}`
            "  return body\n",
            set(),
        ),
    ]
    preview_failures = 0
    for description, source, expected in preview_cases:
        actual = compute_preview_block_lines(source)
        if actual == expected:
            print(f"  ok  {description!r}: lines={sorted(actual)}")
        else:
            preview_failures += 1
            print(
                f"  FAIL {description!r}: got {sorted(actual)}, "
                f"expected {sorted(expected)}"
            )
    print(
        f"Preview block-skip: {len(preview_cases) - preview_failures}/"
        f"{len(preview_cases)} behaved as expected"
    )

    # Path-exclusion regression: `+Previews.swift` files MUST still be
    # excluded by filename filter BEFORE the content-based preview filter
    # runs. The two filters answer the same question at different
    # granularities — whole-file vs inline block — and `+Previews.swift`
    # never reaches `compute_preview_block_lines` because source discovery
    # drops it first. This fixture protects against future "double-count"
    # confusion if a contributor adds a `+Previews.swift` file with
    # non-Preview code (anti-pattern, but the filename filter is intended
    # to be the canonical contract for preview-only files).
    print("Filter-precedence fixtures:")
    precedence_failures = 0
    preview_sidecar = (
        SOURCE_DIR / "Views" / "ModelDownload" / "PromoCard+Previews.swift"
    )
    if is_excluded_path(preview_sidecar):
        print(
            "  ok  '+Previews.swift takes filename precedence over content filter'"
        )
    else:
        precedence_failures += 1
        print(
            "  FAIL '+Previews.swift NOT excluded by filename — content filter "
            "would double-count if reached'"
        )
    print(
        f"Filter-precedence: {1 - precedence_failures}/1 behaved as expected"
    )

    return 0 if (
        failures == 0
        and path_failures == 0
        and preview_failures == 0
        and precedence_failures == 0
    ) else 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Tier 2 i18n leak audit. Surfaces Swift string literals not yet "
            "wrapped in String(localized:). Developer-run only — not a CI "
            "gate (see docs/i18n/leak-detection.md)."
        )
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=SOURCE_DIR,
        help=f"Root to scan (default: {SOURCE_DIR})",
    )
    parser.add_argument(
        "--show-dropped",
        action="store_true",
        help="Print the full list of filtered keys (debugging the filters).",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run filter fixture tests and exit.",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return _self_test()

    if not args.source_dir.is_dir():
        print(f"error: {args.source_dir} not found", file=sys.stderr)
        return 2

    sources = find_swift_sources(args.source_dir)
    if not sources:
        print(f"error: no .swift files under {args.source_dir}", file=sys.stderr)
        return 2

    candidates = extract_potential_keys(sources)
    # Location-based pre-filter: drop candidates inside #Preview macro
    # bodies before key-text noise filters run.
    candidates, preview_dropped = apply_preview_filter(candidates)
    kept, dropped = filter_candidates(candidates)
    if preview_dropped:
        dropped[_PREVIEW_FILTER_NAME] = preview_dropped

    if kept:
        print(format_kept(kept, ROOT))
        print()
    print(format_summary(kept, dropped))

    # Tier 2 is informational — exit 0 even when candidates are present.
    # CI gating is intentionally not wired up; reviewer triages output.
    return 0


if __name__ == "__main__":
    sys.exit(main())
