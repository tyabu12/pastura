#!/usr/bin/env python3
"""Prune ``extractionState: "stale"`` entries from Localizable.xcstrings (Issue #304).

Apple's ``xcstringstool sync`` marks catalog keys as stale when their source
references disappear (e.g., after a rename). Translated stale entries are
preserved by Apple's design — translator work is never auto-discarded. This
script provides opt-in cleanup.

Format-fidelity invariant (load-bearing):

- Apple-canonical xcstrings format uses 2-space indent and ``' : '`` separators.
- The current file does NOT end with a trailing newline.
- ``json.dumps(parsed, indent=2, separators=(',', ' : '), ensure_ascii=False)``
  with no ``+ '\n'`` produces a byte-identical round-trip.
- A 1-byte deviation triggers a multi-thousand-line phantom diff at the next
  ``xcstringstool sync`` (PR #301).
- ``assert_roundtrip_identity`` runs at startup and fails loud if Apple ever
  changes their canonical form, so a corrupting prune cannot be committed by
  accident.

Usage::

    python3 scripts/xcstrings-prune-stale.py                 # list stale (read-only)
    python3 scripts/xcstrings-prune-stale.py --dry-run       # preview without writing
    python3 scripts/xcstrings-prune-stale.py --prune         # remove (interactive)
    python3 scripts/xcstrings-prune-stale.py --prune --keep-translated
    python3 scripts/xcstrings-prune-stale.py --prune --force # CI / scripted

When to run: before i18n Step transitions, or whenever a contributor notices
stale buildup. Not on a schedule. Out of scope per Issue #304: age-aware
pruning, CI auto-prune, threshold-based gating.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
XCSTRINGS_PATH = ROOT / "Pastura" / "Pastura" / "Resources" / "Localizable.xcstrings"


def encode_canonical(parsed: dict) -> bytes:
  """Serialize to Apple-canonical xcstrings JSON.

  Do NOT add ``+ b"\n"`` — see module docstring's format-fidelity invariant.
  """
  return json.dumps(
    parsed, indent=2, separators=(",", " : "), ensure_ascii=False
  ).encode("utf-8")


def assert_roundtrip_identity(raw_bytes: bytes) -> None:
  parsed = json.loads(raw_bytes)
  encoded = encode_canonical(parsed)
  if encoded != raw_bytes:
    sys.exit(
      "ERROR: canonical-format round-trip failed — Apple may have changed "
      "the xcstrings format. Refusing to write to avoid a phantom diff. "
      f"raw={len(raw_bytes)}B encoded={len(encoded)}B. Update "
      "encode_canonical() and re-validate."
    )


def is_stale(entry: dict) -> bool:
  return entry.get("extractionState") == "stale"


def translated_locales(entry: dict) -> list[str]:
  """Return locales of the entry whose stringUnit is in ``translated`` state.

  Locale-agnostic by design — today the catalog is ja-only, but ROADMAP
  Steps C/D will add more locales and ``--keep-translated`` must remain
  correct without code changes.
  """
  out: list[str] = []
  localizations = entry.get("localizations") or {}
  for locale, locale_data in localizations.items():
    if not isinstance(locale_data, dict):
      continue
    string_unit = locale_data.get("stringUnit")
    if isinstance(string_unit, dict) and string_unit.get("state") == "translated":
      out.append(locale)
  return out


def collect_stale(parsed: dict) -> list[tuple[str, dict]]:
  strings = parsed.get("strings") or {}
  return [(k, v) for k, v in strings.items() if isinstance(v, dict) and is_stale(v)]


def _truncate(key: str, limit: int = 80) -> str:
  return key if len(key) <= limit else key[: limit - 3] + "..."


def format_listing(stale: list[tuple[str, dict]]) -> str:
  if not stale:
    return "No stale entries found."
  noun = "entry" if len(stale) == 1 else "entries"
  lines = [f"Found {len(stale)} stale {noun}:"]
  for key, entry in stale:
    locales = translated_locales(entry)
    tag = f"translated [{', '.join(sorted(locales))}]" if locales else "untranslated"
    lines.append(f"  - [{tag}] {_truncate(key)}")
  return "\n".join(lines)


def atomic_write(path: Path, data: bytes) -> None:
  """Write ``data`` to ``path`` via tempfile + ``os.replace``.

  Defends against mid-write Ctrl-C corrupting a file every build reads via
  ``xcstringstool sync`` (.claude/rules/xcodebuild-cli.md Auto-sync). POSIX
  rename atomicity requires same filesystem; using ``path.parent`` satisfies.
  """
  with tempfile.NamedTemporaryFile(
    mode="wb", dir=path.parent, delete=False, prefix=path.name + ".",
  ) as tmp:
    tmp_path = Path(tmp.name)
    try:
      tmp.write(data)
      tmp.flush()
      os.fsync(tmp.fileno())
    except BaseException:
      tmp_path.unlink(missing_ok=True)
      raise
  try:
    os.replace(tmp_path, path)
  except BaseException:
    tmp_path.unlink(missing_ok=True)
    raise


def _entry_word(n: int) -> str:
  return "entry" if n == 1 else "entries"


def main() -> int:
  parser = argparse.ArgumentParser(
    description=(
      "Prune `extractionState: \"stale\"` entries from "
      "Localizable.xcstrings. See Issue #304."
    ),
  )
  mode_group = parser.add_mutually_exclusive_group()
  mode_group.add_argument(
    "--dry-run",
    action="store_true",
    help=(
      "Preview which entries would be removed (subject to --keep-translated)."
      " Does not write."
    ),
  )
  mode_group.add_argument(
    "--prune",
    action="store_true",
    help=(
      "Remove stale entries and write the catalog. Interactive confirmation"
      " unless --force."
    ),
  )
  parser.add_argument(
    "--keep-translated",
    action="store_true",
    help=(
      "Keep stale entries that have at least one locale in `translated` state"
      " (translator work is opt-in to lose)."
    ),
  )
  parser.add_argument(
    "--force",
    action="store_true",
    help=(
      "Skip the interactive confirmation in --prune mode. Required when stdin"
      " is not a TTY."
    ),
  )
  args = parser.parse_args()

  if not XCSTRINGS_PATH.is_file():
    print(f"::error::xcstrings file not found at {XCSTRINGS_PATH}", file=sys.stderr)
    return 2

  raw_bytes = XCSTRINGS_PATH.read_bytes()
  assert_roundtrip_identity(raw_bytes)

  parsed = json.loads(raw_bytes)
  stale = collect_stale(parsed)

  if not args.dry_run and not args.prune:
    if args.keep_translated:
      print(
        "note: --keep-translated has no effect in listing mode; "
        "pass --dry-run or --prune.",
        file=sys.stderr,
      )
    print(format_listing(stale))
    return 0

  if args.keep_translated:
    to_remove = [(k, e) for k, e in stale if not translated_locales(e)]
    kept = [(k, e) for k, e in stale if translated_locales(e)]
  else:
    to_remove = list(stale)
    kept = []

  if not to_remove:
    if stale:
      noun = _entry_word(len(stale))
      verb = "is" if len(stale) == 1 else "are"
      print(
        f"All {len(stale)} stale {noun} {verb} translated; "
        f"--keep-translated leaves them in place. Nothing to do."
      )
    else:
      print("No stale entries found. Nothing to do.")
    return 0

  if args.dry_run:
    print(f"--dry-run: {len(to_remove)} {_entry_word(len(to_remove))} would be removed:")
    for key, entry in to_remove:
      locales = translated_locales(entry)
      tag = f"translated [{', '.join(sorted(locales))}]" if locales else "untranslated"
      print(f"  - [{tag}] {_truncate(key)}")
    if kept:
      print(
        f"--keep-translated: {len(kept)} translated "
        f"{_entry_word(len(kept))} retained."
      )
    return 0

  assert args.prune
  if not args.force:
    if not sys.stdin.isatty():
      print(
        "::error::--prune requires --force when stdin is not a TTY "
        "(prevents silent hang in agent / piped contexts).",
        file=sys.stderr,
      )
      return 2
    print(format_listing(to_remove))
    if kept:
      print(
        f"({len(kept)} translated {_entry_word(len(kept))} will be kept due"
        f" to --keep-translated.)"
      )
    prompt = f"Remove {len(to_remove)} stale {_entry_word(len(to_remove))}? [y/N]: "
    answer = input(prompt).strip().lower()
    if answer not in ("y", "yes"):
      print("Aborted.")
      return 1

  remove_keys = {k for k, _ in to_remove}
  strings = parsed.get("strings") or {}
  parsed["strings"] = {k: v for k, v in strings.items() if k not in remove_keys}

  out_bytes = encode_canonical(parsed)
  atomic_write(XCSTRINGS_PATH, out_bytes)

  print(
    f"Removed {len(to_remove)} stale {_entry_word(len(to_remove))} from "
    f"{XCSTRINGS_PATH.relative_to(ROOT)}."
  )
  if kept:
    print(
      f"({len(kept)} translated {_entry_word(len(kept))} kept due to "
      f"--keep-translated.)"
    )
  return 0


if __name__ == "__main__":
  sys.exit(main())
