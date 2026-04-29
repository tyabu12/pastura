#!/usr/bin/env python3
"""Localization coverage gate for Pastura (Issue #294, ROADMAP § Step A details).

Validates that every top-level key in ``Localizable.xcstrings`` has a complete
``ja`` translation. The script exits non-zero on any of:

1. **Missing localizations** — empty ``{}`` form, or ``localizations`` present
   without a ``ja`` sub-key. (Apple xcstrings represents never-translated keys
   as bare ``{}``; a coverage check that only inspects ``state`` would silently
   pass these.)
2. **Wrong state** — ``state`` other than ``"translated"`` (e.g. ``new`` /
   ``needs_review`` / ``stale``).
3. **Empty value** — ``value`` is missing or zero-length after stripping.
4. **Per-key ``extractionState == "stale"``** — Xcode marks an entry stale when
   the source-code interpolation no longer matches the catalog key. Stale keys
   indicate drift; treat as fail so ``ja`` translations don't silently rot.
5. **``sourceLanguage`` not ``"en"``** — sanity guard for ADR-010 § Step A
   source-language commitment (``en`` is the development language).
6. **Top-level non-ASCII keys** — defensive guard against the reverse-direction
   regression Critic flagged (Q1 cleanup): if ``"キャンセル"`` or any other
   Japanese-source key reappears at the top level, fail.

Run ``--self-test`` to exercise the failure paths against in-memory fixtures
before touching the real catalog. CI invokes the script with no arguments.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_XCSTRINGS = (
    ROOT / "Pastura" / "Pastura" / "Resources" / "Localizable.xcstrings"
)

EXPECTED_SOURCE_LANGUAGE = "en"
REQUIRED_LOCALES = ("ja",)

# CJK script ranges used to detect Japanese-source keys leaking back into the
# top-level catalog (Q1 regen guard). Typographic punctuation like em-dash,
# curly quotes, and ellipsis is allowed in English keys.
_CJK_RANGES: tuple[tuple[int, int], ...] = (
    (0x3040, 0x309F),  # Hiragana
    (0x30A0, 0x30FF),  # Katakana
    (0x4E00, 0x9FFF),  # CJK Unified Ideographs (Han)
    (0xFF00, 0xFFEF),  # Halfwidth and Fullwidth Forms
)


def _has_cjk_chars(s: str) -> bool:
    return any(
        any(lo <= ord(c) <= hi for lo, hi in _CJK_RANGES) for c in s
    )


def validate_catalog(data: dict[str, Any]) -> list[str]:
    """Returns a list of error messages. Empty list means coverage is 100%."""
    errors: list[str] = []

    source_language = data.get("sourceLanguage")
    if source_language != EXPECTED_SOURCE_LANGUAGE:
        errors.append(
            f"sourceLanguage = {source_language!r}, expected "
            f"{EXPECTED_SOURCE_LANGUAGE!r} (per ADR-010)"
        )

    strings = data.get("strings", {})
    if not isinstance(strings, dict):
        errors.append(f"`strings` must be an object, got {type(strings).__name__}")
        return errors

    for key, entry in strings.items():
        if _has_cjk_chars(key):
            errors.append(
                f"top-level key contains CJK characters: {key!r} — source "
                "language is en, so a Japanese-source key has reappeared "
                "(likely Xcode auto-extraction regenerating a removed key). "
                "Fix the source-code call site to use the English-source key."
            )
            # Continue checking — a key with CJK name might still be malformed.

        if not isinstance(entry, dict):
            errors.append(f"{key!r}: entry must be an object")
            continue

        for required_locale in REQUIRED_LOCALES:
            errors.extend(_validate_locale(key, entry, required_locale))

    return errors


def _validate_locale(key: str, entry: dict[str, Any], locale: str) -> list[str]:
    errors: list[str] = []

    localizations = entry.get("localizations")
    if not isinstance(localizations, dict) or locale not in localizations:
        errors.append(
            f"{key!r}: missing {locale!r} localization "
            "(empty `{}` form or absent `localizations.<locale>`)"
        )
        return errors

    locale_payload = localizations[locale]
    if not isinstance(locale_payload, dict):
        errors.append(f"{key!r}: {locale!r} payload is not an object")
        return errors

    extraction_state = locale_payload.get("extractionState")
    if extraction_state == "stale":
        errors.append(
            f"{key!r}: {locale!r} extractionState == 'stale' "
            "(Xcode flagged drift between source code and catalog — "
            "re-extract or remove the key)"
        )

    string_unit = locale_payload.get("stringUnit")
    if not isinstance(string_unit, dict):
        errors.append(f"{key!r}: {locale!r} missing `stringUnit`")
        return errors

    state = string_unit.get("state")
    if state != "translated":
        errors.append(
            f"{key!r}: {locale!r} state = {state!r}, expected 'translated'"
        )

    value = string_unit.get("value", "")
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{key!r}: {locale!r} value is empty or missing")

    return errors


def _self_test() -> int:
    """Exercise each failure mode against in-memory fixtures."""

    def make_valid_entry(value: str = "テスト") -> dict[str, Any]:
        return {
            "localizations": {
                "ja": {
                    "stringUnit": {"state": "translated", "value": value}
                }
            }
        }

    def expect_pass(name: str, data: dict[str, Any]) -> bool:
        errors = validate_catalog(data)
        if errors:
            print(f"  FAIL: '{name}' should pass but got {len(errors)} errors:")
            for err in errors:
                print(f"    · {err}")
            return False
        print(f"  ok: '{name}'")
        return True

    def expect_fail(
        name: str, data: dict[str, Any], must_contain: str
    ) -> bool:
        errors = validate_catalog(data)
        if not errors:
            print(f"  FAIL: '{name}' should fail but passed")
            return False
        if not any(must_contain in err for err in errors):
            print(
                f"  FAIL: '{name}' failed but no error contained "
                f"{must_contain!r}: {errors}"
            )
            return False
        print(f"  ok: '{name}'")
        return True

    print("Self-test fixtures:")
    results: list[bool] = []

    # 1. Happy path
    results.append(
        expect_pass(
            "valid catalog",
            {"sourceLanguage": "en", "strings": {"Hello": make_valid_entry()}},
        )
    )

    # 2. Empty `{}` form
    results.append(
        expect_fail(
            "empty `{}` entry",
            {"sourceLanguage": "en", "strings": {"Hello": {}}},
            "missing 'ja' localization",
        )
    )

    # 3. localizations dict but no `ja` key
    results.append(
        expect_fail(
            "localizations without ja",
            {
                "sourceLanguage": "en",
                "strings": {
                    "Hello": {
                        "localizations": {
                            "fr": {
                                "stringUnit": {
                                    "state": "translated",
                                    "value": "Bonjour",
                                }
                            }
                        }
                    }
                },
            },
            "missing 'ja' localization",
        )
    )

    # 4. State = new
    new_entry = {
        "localizations": {
            "ja": {"stringUnit": {"state": "new", "value": "テスト"}}
        }
    }
    results.append(
        expect_fail(
            "state = new",
            {"sourceLanguage": "en", "strings": {"Hello": new_entry}},
            "state = 'new'",
        )
    )

    # 5. Empty value
    empty_value_entry = {
        "localizations": {
            "ja": {"stringUnit": {"state": "translated", "value": ""}}
        }
    }
    results.append(
        expect_fail(
            "empty value",
            {"sourceLanguage": "en", "strings": {"Hello": empty_value_entry}},
            "value is empty",
        )
    )

    # 6. Whitespace-only value
    whitespace_entry = {
        "localizations": {
            "ja": {"stringUnit": {"state": "translated", "value": "   "}}
        }
    }
    results.append(
        expect_fail(
            "whitespace-only value",
            {
                "sourceLanguage": "en",
                "strings": {"Hello": whitespace_entry},
            },
            "value is empty",
        )
    )

    # 7. extractionState = stale on the locale payload
    stale_entry = {
        "localizations": {
            "ja": {
                "extractionState": "stale",
                "stringUnit": {"state": "translated", "value": "テスト"},
            }
        }
    }
    results.append(
        expect_fail(
            "extractionState stale",
            {"sourceLanguage": "en", "strings": {"Hello": stale_entry}},
            "extractionState == 'stale'",
        )
    )

    # 8. sourceLanguage != en
    results.append(
        expect_fail(
            "sourceLanguage = ja",
            {"sourceLanguage": "ja", "strings": {"Hello": make_valid_entry()}},
            "sourceLanguage =",
        )
    )

    # 9. CJK top-level key (Q1 regen guard)
    results.append(
        expect_fail(
            "CJK top-level key",
            {
                "sourceLanguage": "en",
                "strings": {"キャンセル": make_valid_entry()},
            },
            "CJK characters",
        )
    )

    # 10. English key with typographic Unicode (em-dash, curly quotes, ellipsis,
    #     fullwidth-arrow) must NOT trigger the CJK guard — these are valid
    #     English keys present in the live catalog (e.g. "Loading…").
    typographic_keys = [
        "Lightweight reasoning mode — faster responses, leaner footprint.",
        "A scenario named “%arg” already uses this id.",
        "Loading gallery…",
        "↳ sub-phase",
    ]
    typographic_data = {
        "sourceLanguage": "en",
        "strings": {k: make_valid_entry() for k in typographic_keys},
    }
    results.append(
        expect_pass("typographic Unicode in English keys", typographic_data)
    )

    passed = sum(results)
    total = len(results)
    print(f"Self-test: {passed}/{total} fixtures behaved as expected")
    return 0 if passed == total else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validates Pastura's Localizable.xcstrings ja coverage. "
            "Exits non-zero on any uncovered key, drift, or sanity-check "
            "violation."
        )
    )
    parser.add_argument(
        "--xcstrings",
        type=Path,
        default=DEFAULT_XCSTRINGS,
        help=f"Path to Localizable.xcstrings (default: {DEFAULT_XCSTRINGS})",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run in-memory fixture tests for the validator and exit.",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return _self_test()

    if not args.xcstrings.is_file():
        print(f"error: {args.xcstrings} not found", file=sys.stderr)
        return 2

    try:
        with args.xcstrings.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"error: {args.xcstrings}: invalid JSON — {exc}", file=sys.stderr)
        return 2

    errors = validate_catalog(data)
    total_keys = len(data.get("strings", {}))

    if errors:
        print(
            f"❌ Localization coverage check failed: "
            f"{len(errors)} issue(s) across {total_keys} keys",
            file=sys.stderr,
        )
        for err in errors:
            print(f"  · {err}", file=sys.stderr)
        return 1

    print(f"✅ Localization coverage OK: {total_keys} keys, all `ja` translated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
