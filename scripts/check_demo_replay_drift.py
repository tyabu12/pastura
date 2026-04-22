#!/usr/bin/env python3
"""Drift guard for bundled DL-time demo replays (Issue #170, spec §3.3 / §5.2).

At build time, re-hashes each shipped preset YAML and compares against each
bundled demo's ``preset_ref.yaml_sha256``. Also enforces the curation
quality floors from spec §5.2 and the §3.4 filter-audit attestation.

Runtime-vs-CI asymmetry (intentional, spec §3.3 / §7.6): the Swift
``BundledDemoReplaySource`` loader only validates integrity (SHA +
``schema_version``) and silent-skips the rest — the DL demo surface is
ambient, so user-visible hard errors are worse than a shorter rotation.
The curation-quality checks below (``content_filter_applied``, turns
count, language, bundle size) are build-time gates only; do not move
them into the Swift loader. If you need to relax a check, edit both
this script and the corresponding spec section.

Hash parity invariant (load-bearing): ``sha256_hex`` below MUST be
byte-identical to ``Pastura/App/ReplayHashing.swift``'s ``sha256Hex``.
Both read the file as UTF-8 text then re-encode to UTF-8 bytes — any
deviation (hashing raw file bytes, BOM stripping difference, CRLF
normalisation) would silent-skip bundled demos in production or pass
drift at build time while failing at runtime.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
PRESETS_DIR = ROOT / "Pastura" / "Pastura" / "Resources" / "Presets"
DEMOS_DIR = ROOT / "Pastura" / "Pastura" / "Resources" / "DemoReplays"

MIN_DEMOS = 3
MAX_TOTAL_BYTES = 3 * 1024 * 1024
MAX_PER_FILE_BYTES = 1 * 1024 * 1024
MIN_TURNS = 6
REQUIRED_SCHEMA_VERSION = 1
REQUIRED_LANGUAGE = "ja"
# Mirror BundledDemoReplaySource.demoFilenameSuffix — demos on disk use
# `<slug>_demo.yaml` so Xcode's synchronized-group flat-bundle copy does
# not collide with preset `<slug>.yaml` files.
DEMO_FILENAME_SUFFIX = "_demo"


def sha256_hex(text: str) -> str:
  """Match ``ReplayHashing.sha256Hex`` byte-for-byte.

  Swift: ``SHA256.hash(data: Data(source.utf8))`` where ``source`` is a
  ``String`` decoded via ``String(contentsOf:encoding:.utf8)``. Python
  mirrors: ``Path.read_text(encoding="utf-8")`` produces the decoded
  ``str``, ``.encode("utf-8")`` produces the same UTF-8 bytes Swift's
  ``Data(source.utf8)`` does. Hashing those bytes matches.
  """
  return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_text(path: Path) -> str:
  return path.read_text(encoding="utf-8")


def load_preset_shas() -> dict[str, str]:
  """Return ``{preset_id: sha256_hex}`` for every shipped preset."""
  shas: dict[str, str] = {}
  for yaml_path in sorted(PRESETS_DIR.glob("*.yaml")):
    text = read_text(yaml_path)
    try:
      parsed = yaml.safe_load(text)
    except yaml.YAMLError as exc:
      raise SystemExit(f"::error::Preset {yaml_path.name}: {exc}")
    if not isinstance(parsed, dict):
      raise SystemExit(
        f"::error::Preset {yaml_path.name}: top-level is not a mapping"
      )
    preset_id = parsed.get("id")
    if not isinstance(preset_id, str) or not preset_id:
      raise SystemExit(f"::error::Preset {yaml_path.name}: no 'id' field")
    shas[preset_id] = sha256_hex(text)
  return shas


def validate_demo(path: Path, preset_shas: dict[str, str]) -> list[str]:
  errors: list[str] = []
  size = path.stat().st_size
  if size > MAX_PER_FILE_BYTES:
    errors.append(
      f"{path.name}: size {size} > {MAX_PER_FILE_BYTES} bytes "
      f"(spec §5.2 per-file ceiling)"
    )

  text = read_text(path)
  try:
    doc = yaml.safe_load(text)
  except yaml.YAMLError as exc:
    errors.append(f"{path.name}: YAML parse error: {exc}")
    return errors
  if not isinstance(doc, dict):
    errors.append(f"{path.name}: top-level is not a mapping")
    return errors

  schema_version = doc.get("schema_version")
  if schema_version != REQUIRED_SCHEMA_VERSION:
    errors.append(
      f"{path.name}: schema_version {schema_version!r} != "
      f"{REQUIRED_SCHEMA_VERSION} (spec §3.2)"
    )

  preset_ref = doc.get("preset_ref")
  if not isinstance(preset_ref, dict):
    errors.append(f"{path.name}: preset_ref missing or not a mapping")
  else:
    preset_id = preset_ref.get("id")
    recorded_sha = preset_ref.get("yaml_sha256")
    if not isinstance(preset_id, str) or not preset_id:
      errors.append(f"{path.name}: preset_ref.id missing")
    elif preset_id not in preset_shas:
      errors.append(
        f"{path.name}: preset_ref.id {preset_id!r} is not a shipped preset "
        f"(shipped: {sorted(preset_shas)})"
      )
    elif not isinstance(recorded_sha, str) or not recorded_sha:
      errors.append(f"{path.name}: preset_ref.yaml_sha256 missing")
    elif recorded_sha != preset_shas[preset_id]:
      errors.append(
        f"{path.name}: preset_ref.yaml_sha256 mismatch for {preset_id!r} "
        f"(recorded {recorded_sha}, current preset hashes to "
        f"{preset_shas[preset_id]}). Re-record the demo or run "
        f"`scripts/check_demo_replay_drift.py --fix` if the preset "
        f"edit is intentional and the demo content is still accurate."
      )

  metadata = doc.get("metadata")
  if not isinstance(metadata, dict):
    errors.append(f"{path.name}: metadata missing or not a mapping")
  else:
    language = metadata.get("language")
    if language != REQUIRED_LANGUAGE:
      errors.append(
        f"{path.name}: metadata.language {language!r} != "
        f"{REQUIRED_LANGUAGE!r} (Phase 2 is JA-only, spec §5.5)"
      )
    if metadata.get("content_filter_applied") is not True:
      errors.append(
        f"{path.name}: metadata.content_filter_applied must be true "
        f"after manual audit (spec §3.4)"
      )

  turns = doc.get("turns")
  if not isinstance(turns, list):
    errors.append(f"{path.name}: turns missing or not a list")
  elif len(turns) < MIN_TURNS:
    errors.append(
      f"{path.name}: turns count {len(turns)} < {MIN_TURNS} (spec §5.2)"
    )

  return errors


_SHA_LINE_RE = re.compile(
  r"(^\s*yaml_sha256:\s*)(?:['\"]?)([0-9a-f]*)(?:['\"]?)\s*$",
  re.MULTILINE,
)


def _replace_sha_in_yaml(text: str, new_sha: str) -> str:
  return _SHA_LINE_RE.sub(lambda m: f"{m.group(1)}'{new_sha}'", text, count=1)


def fix_demos(preset_shas: dict[str, str]) -> int:
  """Rewrite each demo's ``yaml_sha256`` to the current shipped preset hash.

  Curator workflow: edit a preset → run ``--fix`` → review diff → commit.
  Removes manual SHA copy-paste as an error source. Only the
  ``yaml_sha256`` field is touched; formatting and comments are preserved.
  """
  changed = 0
  for demo_path in sorted(DEMOS_DIR.glob(f"*{DEMO_FILENAME_SUFFIX}.yaml")):
    text = read_text(demo_path)
    try:
      doc = yaml.safe_load(text)
    except yaml.YAMLError:
      continue
    if not isinstance(doc, dict):
      continue
    preset_ref = doc.get("preset_ref")
    if not isinstance(preset_ref, dict):
      continue
    preset_id = preset_ref.get("id")
    if not isinstance(preset_id, str):
      continue
    expected = preset_shas.get(preset_id)
    if not expected:
      continue
    recorded = preset_ref.get("yaml_sha256")
    if recorded == expected:
      continue
    new_text = _replace_sha_in_yaml(text, expected)
    if new_text == text:
      # SHA line not present — leave it to the regular validator to flag.
      continue
    demo_path.write_text(new_text, encoding="utf-8")
    changed += 1
    print(f"fixed {demo_path.name}: yaml_sha256 -> {expected}")
  return changed


def main() -> int:
  parser = argparse.ArgumentParser(
    description=(
      "Validate bundled DL-time demo replays against shipped presets. "
      "See docs/specs/demo-replay-spec.md §3.3, §3.4, §5.2."
    )
  )
  parser.add_argument(
    "--fix",
    action="store_true",
    help=(
      "Rewrite each demo's preset_ref.yaml_sha256 with the current "
      "shipped preset's hash. Review the diff and commit. Use after "
      "an intentional preset edit whose demo content is still accurate."
    ),
  )
  args = parser.parse_args()

  if not PRESETS_DIR.is_dir():
    print(f"::error::Presets dir not found at {PRESETS_DIR}", file=sys.stderr)
    return 2
  preset_shas = load_preset_shas()

  if args.fix:
    if not DEMOS_DIR.is_dir():
      print(f"DemoReplays/ dir not found at {DEMOS_DIR}; nothing to fix.")
      return 0
    changed = fix_demos(preset_shas)
    if changed == 0:
      print("No SHA drift detected; nothing to fix.")
    else:
      print(f"{changed} file(s) updated. Review the diff and commit.")
    return 0

  if not DEMOS_DIR.is_dir():
    print(
      f"::error::DemoReplays/ dir not found at {DEMOS_DIR}. "
      f"Spec §5.2 floor (>= {MIN_DEMOS}) not met.",
      file=sys.stderr,
    )
    return 1

  demo_paths = sorted(DEMOS_DIR.glob(f"*{DEMO_FILENAME_SUFFIX}.yaml"))
  errors: list[str] = []

  if len(demo_paths) < MIN_DEMOS:
    errors.append(
      f"DemoReplays/ has {len(demo_paths)} file(s); spec §5.2 requires "
      f">= {MIN_DEMOS}"
    )

  total_bytes = sum(p.stat().st_size for p in demo_paths)
  if total_bytes > MAX_TOTAL_BYTES:
    errors.append(
      f"DemoReplays/ total size {total_bytes} > {MAX_TOTAL_BYTES} bytes "
      f"(spec §5.2)"
    )

  for demo_path in demo_paths:
    errors.extend(validate_demo(demo_path, preset_shas))

  if errors:
    print("::error::Demo replay drift guard FAILED", file=sys.stderr)
    for err in errors:
      print(f"  - {err}", file=sys.stderr)
    return 1

  print(
    f"Drift guard OK: {len(demo_paths)} demo(s), total {total_bytes} bytes, "
    f"{len(preset_shas)} shipped preset(s)."
  )
  return 0


if __name__ == "__main__":
  sys.exit(main())
