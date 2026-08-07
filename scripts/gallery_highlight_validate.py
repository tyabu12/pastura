#!/usr/bin/env python3
"""Validate `docs/gallery/highlights/<id>.json` against ADR-029.

Two consumers, one implementation:

  1. `scripts/check-gallery-entry.sh` runs this as a CLI (`--gallery-json` /
     `--gallery-dir` / `--blocklist`). That is the **enforcement point**
     (ADR-029 Decision 2): a hand-edited highlight never runs the extractor,
     so every rule must be re-derivable here, ungated, in CI.
  2. `scripts/gallery_highlight_extract.py` imports `check_content` as a
     fail-fast convenience before it writes anything.

Hashing is **raw-byte** (`hashlib.sha256` over bytes read in binary mode),
matching `shasum -a 256` and the existing gallery trust chain
(`check-gallery-entry.sh`, `URLSessionGalleryService`). It is deliberately
NOT `scripts/jsonl_to_demo_replay.py`'s `sha256_hex`, which hashes UTF-8
*text* for the demo-replay drift check — different trust root (ADR-029
Decision 1).

Prerequisite: **PyYAML** (`python3 -m pip install 'pyyaml>=6,<7'`), needed to
re-derive the shape a `yaml_hook.kind: persona` fragment promises. CI installs
it in the same job that runs the gate. If it is missing, a `persona` hook fails
with a named message rather than passing unverified — a gate that skips a check
when a dependency is absent is worse than one that is loud about it.

Exit code: 0 when every highlight passes, 1 otherwise. Each failure is one
line on stdout prefixed `highlight: <check> — …` so the bash gate can
aggregate them and a reader can grep a specific class.
"""
import argparse
import hashlib
import json
import math
import os
import re
import sys
import unicodedata

try:
    import yaml
except ImportError:  # reported as a failure below, never silently skipped
    yaml = None

SCHEMA_VERSION = 1
EXCERPT_MAX = 8

# ADR-029 Decision 1 — the `yaml_hook.kind` allowlist. `persona` promises the
# fragment parses as persona mappings, which licenses the app's
# editor-vocabulary rendition; `raw` claims no structure and is drawn as a YAML
# block, which is what both surfaces did before the discriminator existed
# (§ Amendment 2026-08-08).
YAML_HOOK_KINDS = frozenset({"persona", "raw"})

# A `kind: persona` fragment's mappings may name only these. `secret:` is
# rejected by name: a hidden agenda is a spoiler wherever it appears, and
# Decision 2's secret branch is designed-untested.
PERSONA_FRAGMENT_KEYS = frozenset({"name", "description"})

# ADR-029 Decision 3 — the full PhaseType catalog at last sync with
# `Pastura/Pastura/Models/PhaseType.swift` (raw values). A transcript phase
# outside this set means a new phase type landed (ADR-022 extension
# contract) and its visibility/outcome classification is unassigned.
PHASE_TYPES = frozenset({
    "speak_all", "speak_each", "vote", "choose", "reflect", "whisper",
    "score_calc", "assign", "eliminate", "summarize", "conditional",
    "event_inject", "relationship_update", "narrate",
})

# A persona's public, in-fiction utterance — the only excerpt-eligible output.
ELIGIBLE_PHASES = frozenset({"speak_all", "speak_each"})

# Outcome disclosures. An utterance is ineligible if any of these precedes it
# in the same round's phase list (ADR-029 Decision 3, position rule part 1).
OUTCOME_PHASES = frozenset({"vote", "eliminate", "score_calc", "choose", "summarize"})

# Field-level allowlist: speak phases also emit `inner_thought`.
SOURCE_FIELDS = frozenset({"statement"})


# --- Hashing + text normalization ------------------------------------------


def sha256_file(path):
    """Raw-byte SHA-256, `shasum -a 256`-equivalent (ADR-029 Decision 1)."""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def normalize(text):
    """Case- and diacritic-insensitive form for blocklist matching.

    NFD-decompose, drop combining marks, casefold — the same match semantics
    the demo-replay audit procedure pins (ADR-005 §5.2).
    """
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(c for c in decomposed if not unicodedata.combining(c))
    return stripped.casefold()


def load_blocklist(path):
    """-> [(normalized_term, contentCategory, index)] from ContentBlocklist.json."""
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    out = []
    for i, entry in enumerate(doc.get("patterns") or []):
        term = normalize((entry or {}).get("term") or "")
        # Filter on the NORMALIZED form: a term of only combining marks
        # normalizes to "" and would substring-match everything.
        if term:
            out.append((term, (entry or {}).get("contentCategory", "?"), i))
    return out


# --- Content checks (shared with the extractor) -----------------------------


def _audited_strings(doc):
    """Every published string, paired with a locator for the failure message."""
    out = []
    for i, ex in enumerate(doc.get("excerpt") or []):
        if isinstance(ex, dict) and isinstance(ex.get("text"), str):
            out.append((f"excerpt[{i}].text", ex["text"]))
    hook = doc.get("yaml_hook")
    if isinstance(hook, dict):
        for key in ("fragment", "caption"):
            if isinstance(hook.get(key), str):
                out.append((f"yaml_hook.{key}", hook[key]))
    if isinstance(doc.get("teaser"), str):
        out.append(("teaser", doc["teaser"]))
    return out


def check_blocklist(doc, blocklist, where):
    """Blocklist audit. Reports the term's *index and category*, never the term."""
    failures = []
    for locator, text in _audited_strings(doc):
        haystack = normalize(text)
        for term, category, index in blocklist:
            if term in haystack:
                failures.append(
                    f"highlight: blocklist — {where} {locator} matches "
                    f"ContentBlocklist patterns[{index}] (category={category}). "
                    "Re-curate the excerpt; the term itself is withheld here.")
    return failures


def _check_schema(doc, where):
    failures = []
    sv = doc.get("schema_version")
    if not isinstance(sv, int) or isinstance(sv, bool) or sv != SCHEMA_VERSION:
        failures.append(
            f"highlight: schema — {where} schema_version must be {SCHEMA_VERSION}, "
            f"got {sv!r}")
    ref = doc.get("scenario_ref")
    if not isinstance(ref, dict) or not isinstance(ref.get("id"), str) \
            or not isinstance(ref.get("yaml_sha256"), str):
        failures.append(
            f"highlight: schema — {where} scenario_ref must be "
            "{id: str, yaml_sha256: str}")
    src = doc.get("source")
    if not isinstance(src, dict) or not all(
            isinstance(src.get(k), str) for k in ("model", "run_id", "generated_at")):
        failures.append(
            f"highlight: schema — {where} source must be "
            "{model: str, run_id: str, generated_at: str}")
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or not isinstance(hook.get("fragment"), str) \
            or not isinstance(hook.get("caption"), str) \
            or not isinstance(hook.get("kind"), str):
        failures.append(
            f"highlight: schema — {where} yaml_hook must be "
            "{kind: str, fragment: str, caption: str}")
    elif hook["kind"] not in YAML_HOOK_KINDS:
        failures.append(
            f"highlight: yaml_hook kind — {where} yaml_hook.kind={hook['kind']!r} is "
            f"not in the allowlist {sorted(YAML_HOOK_KINDS)}. Adding a value means "
            "designing its reading side first (ADR-029 revisit trigger); until then "
            "`raw` publishes the fragment as a YAML block")
    if not isinstance(doc.get("teaser"), str) or not doc.get("teaser").strip():
        failures.append(f"highlight: schema — {where} teaser must be a non-empty string")
    if not isinstance(doc.get("window_override"), bool):
        failures.append(f"highlight: schema — {where} window_override must be a boolean")
    if doc.get("content_filter_applied") is not True:
        failures.append(
            f"highlight: content_filter_applied — {where} must be exactly true "
            "(the publish-time blocklist audit attestation, ADR-029 Decision 2)")
    return failures


def _check_excerpt_shape(doc, where):
    failures = []
    excerpt = doc.get("excerpt")
    if not isinstance(excerpt, list) or not excerpt:
        return [f"highlight: schema — {where} excerpt must be a non-empty array"]
    if len(excerpt) > EXCERPT_MAX:
        failures.append(
            f"highlight: excerpt cap — {where} has {len(excerpt)} entries, "
            f"cap is {EXCERPT_MAX} (ADR-029 Decision 1)")
    for i, ex in enumerate(excerpt):
        loc = f"{where} excerpt[{i}]"
        if not isinstance(ex, dict):
            failures.append(f"highlight: schema — {loc} must be an object")
            continue
        if not isinstance(ex.get("agent"), str) or not ex["agent"]:
            failures.append(f"highlight: schema — {loc}.agent must be a non-empty string")
        if not isinstance(ex.get("text"), str) or not ex["text"].strip():
            failures.append(f"highlight: schema — {loc}.text must be a non-empty string")
        if not isinstance(ex.get("round"), int) or isinstance(ex.get("round"), bool) \
                or ex["round"] < 1:
            failures.append(f"highlight: schema — {loc}.round must be an integer >= 1")
        if not isinstance(ex.get("phase_index"), int) \
                or isinstance(ex.get("phase_index"), bool) or ex["phase_index"] < 0:
            failures.append(f"highlight: schema — {loc}.phase_index must be an integer >= 0")
        phase = ex.get("phase")
        if phase not in PHASE_TYPES:
            failures.append(
                f"highlight: unknown phase — {loc}.phase={phase!r} is outside the "
                "PhaseType catalog (a new phase type landed — classify it in "
                "ADR-029 Decision 3 first)")
        elif phase not in ELIGIBLE_PHASES:
            failures.append(
                f"highlight: phase not excerpt-eligible — {loc}.phase={phase!r}; only "
                f"{sorted(ELIGIBLE_PHASES)} output may be excerpted (ADR-029 Decision 3)")
        if ex.get("source_field") not in SOURCE_FIELDS:
            failures.append(
                f"highlight: source_field — {loc}.source_field="
                f"{ex.get('source_field')!r} is not in the allowlist "
                f"{sorted(SOURCE_FIELDS)} (ADR-029 Decision 3)")
    return failures


def _persona_entries(parsed):
    """-> the entry list for either accepted persona-fragment shape, else None.

    ADR-029 Decision 1 pins two: a bare block sequence of mappings (what both
    shipped hooks use — PyYAML parses one at any indent without dedenting) or a
    `personas:`-keyed mapping holding one.
    """
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict) and set(parsed) == {"personas"} \
            and isinstance(parsed["personas"], list):
        return parsed["personas"]
    return None


def _top_level_shape(parsed):
    """A short description of what the fragment parsed to, for the failure text.

    Without it, a `personas:` fragment carrying a sibling key reads as "not a
    persona list" — untrue on its face, since it does have `personas:`. Naming
    the keys tells the curator which one to drop.
    """
    if isinstance(parsed, dict):
        return "a mapping with keys " + str(sorted(map(str, parsed)))
    if isinstance(parsed, list):
        return f"a {len(parsed)}-item sequence"
    return f"{type(parsed).__name__}"


def _check_yaml_hook_secret(doc, where):
    """No published fragment may declare `secret:`, whatever its kind.

    Keyed on the **spoiler**, not on the discriminator. The rule reads "a
    hidden agenda is a spoiler wherever it appears" (ADR-029 Decision 3's
    `assign` rule, applied to the hook), and `kind: raw` is where a curator is
    most likely to paste an unreviewed block — it is published verbatim on both
    surfaces, so a `raw` leak is strictly worse than a `persona` one.

    A line scan rather than a parse, because `raw` licenses no shape and so
    cannot be parsed. That is deliberately conservative: it also fires on a
    `secret:` inside a quoted scalar, which is a false positive a curator can
    resolve by rewording. The alternative — missing a real one — is not
    recoverable once published.

    This is the gate's only `secret:` check on the hook. The extractor's
    hard-fail (`declares_secret`) reads the *scenario YAML*, so nothing had
    ever re-derived the rule for the hook's own text, and a hand-edited hook
    never runs the extractor at all (Decision 2's standing argument).
    """
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or not isinstance(hook.get("fragment"), str):
        return []
    for i, line in enumerate(hook["fragment"].splitlines()):
        if re.match(r"^\s*(-\s+)?secret\s*:", line):
            return [
                f"highlight: yaml_hook secret — {where} yaml_hook.fragment line {i + 1} "
                "declares `secret:`. A hidden agenda is a spoiler wherever it appears, "
                "and ADR-029 Decision 2's secret branch is designed-untested — the "
                "extractor refuses such scenarios, and this is the gate's copy that a "
                "hand-edited hook cannot bypass, in any kind"]
    return []


def _check_yaml_hook_fragment(doc, where):
    """`kind: persona` promises a shape — re-derive it (ADR-029 Decision 1).

    Two reasons this lives in the gate rather than only in the extractor. A
    hand-edited hook never runs the extractor, which is Decision 2's standing
    argument; and the app renders a `persona` fragment in the visual editor's
    vocabulary, so a shape it cannot parse must fail at supply time instead of
    degrading in a client the repo cannot update (§ Amendment 2026-08-08).

    `secret:` is **not** checked here — it is kind-independent, so it lives in
    ``_check_yaml_hook_secret``. Keying it on `persona` would have left the
    verbatim-published `raw` kind unguarded.
    """
    hook = doc.get("yaml_hook")
    if not isinstance(hook, dict) or hook.get("kind") != "persona":
        return []
    fragment = hook.get("fragment")
    if not isinstance(fragment, str):
        return []  # already reported by _check_schema
    if yaml is None:
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona, but PyYAML is not "
            "importable so the fragment's shape cannot be verified. Install it "
            "(python3 -m pip install 'pyyaml>=6,<7'); this check fails closed rather "
            "than passing unverified"]
    try:
        parsed = yaml.safe_load(fragment)
    except yaml.YAMLError as exc:
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona but the fragment is "
            f"not parseable YAML: {exc}"]

    entries = _persona_entries(parsed)
    if not entries:
        return [
            f"highlight: yaml_hook fragment — {where} kind=persona but the fragment is "
            "not a non-empty persona list (expected a block sequence of mappings, or a "
            "`personas:` key holding one; parsed top level was "
            f"{_top_level_shape(parsed)}). Use kind=raw to publish it as YAML instead"]

    failures = []
    for i, item in enumerate(entries):
        loc = f"{where} yaml_hook.fragment[{i}]"
        if not isinstance(item, dict):
            failures.append(f"highlight: yaml_hook fragment — {loc} must be a mapping")
            continue
        # `secret` is reported once, kind-independently, by
        # `_check_yaml_hook_secret`; excluded here so it is not named twice.
        # `map(str, …)` because YAML keys need not be strings — `1: c` alongside
        # `mood: x` makes a bare `sorted()` raise TypeError, which would abort
        # the run with a traceback instead of the one-failure-per-line contract
        # this module's docstring promises.
        rest = sorted(map(str, set(item) - PERSONA_FRAGMENT_KEYS - {"secret"}))
        if rest:
            failures.append(
                f"highlight: yaml_hook fragment — {loc} has key(s) {rest} outside the "
                f"allowlist {sorted(PERSONA_FRAGMENT_KEYS)}")
        for key in sorted(PERSONA_FRAGMENT_KEYS):
            value = item.get(key)
            if not isinstance(value, str) or not value.strip():
                failures.append(
                    f"highlight: yaml_hook fragment — {loc}.{key} must be a non-empty "
                    "string (the app draws both fields)")
    return failures


def _check_position(doc, entry, where):
    """Decision 3's two-part position rule, against the index entry."""
    failures = []
    phases = entry.get("phases")
    rounds = entry.get("rounds")
    if not isinstance(phases, list) or not phases:
        return [f"highlight: schema — {where} gallery.json entry has no `phases` list "
                "to check the within-round bound against"]
    if not isinstance(rounds, int) or isinstance(rounds, bool) or rounds < 1:
        return [f"highlight: schema — {where} gallery.json entry has no usable "
                "`rounds` value to compute the round window"]
    window = math.ceil(rounds / 2)
    override = doc.get("window_override") is True
    for i, ex in enumerate(doc.get("excerpt") or []):
        if not isinstance(ex, dict):
            continue
        loc = f"{where} excerpt[{i}]"
        idx = ex.get("phase_index")
        if isinstance(idx, int) and not isinstance(idx, bool) and 0 <= idx < len(phases):
            if phases[idx] != ex.get("phase"):
                failures.append(
                    f"highlight: phase_index mismatch — {loc}.phase_index={idx} names "
                    f"phases[{idx}]={phases[idx]!r} but phase={ex.get('phase')!r}")
            preceding = [p for p in phases[:idx] if p in OUTCOME_PHASES]
            if preceding:
                failures.append(
                    f"highlight: within-round bound — {loc}.phase_index={idx} is "
                    f"preceded in the round by outcome-class phase(s) {preceding}; "
                    "dialogue reacting to an in-round outcome leaks it "
                    "(ADR-029 Decision 3)")
        elif isinstance(idx, int) and not isinstance(idx, bool):
            failures.append(
                f"highlight: phase_index mismatch — {loc}.phase_index={idx} is outside "
                f"the entry's phases list (len={len(phases)})")
        rnd = ex.get("round")
        if isinstance(rnd, int) and not isinstance(rnd, bool):
            if rnd > rounds:
                failures.append(
                    f"highlight: round window — {loc}.round={rnd} exceeds the "
                    f"scenario's rounds={rounds}")
            elif rnd > window and not override:
                failures.append(
                    f"highlight: round window — {loc}.round={rnd} is outside the "
                    f"default window 1..{window} (rounds={rounds}); pass "
                    "--window-override at extraction to record window_override: true")
    return failures


def check_content(doc, entry, blocklist, where):
    """Every rule derivable from the highlight doc + its index entry.

    Shared by the extractor (fail-fast) and the gate (enforcement). Excludes
    the file-level checks (pairing, file hashes) the extractor cannot run.
    """
    failures = _check_schema(doc, where)
    failures += _check_excerpt_shape(doc, where)
    failures += _check_yaml_hook_secret(doc, where)
    failures += _check_yaml_hook_fragment(doc, where)
    failures += _check_position(doc, entry, where)
    failures += check_blocklist(doc, blocklist, where)
    return failures


# --- Repository-level gate --------------------------------------------------


def _entry_index(gallery_json):
    with open(gallery_json, encoding="utf-8") as f:
        return json.load(f).get("scenarios") or []


def validate_repo(gallery_json, gallery_dir, blocklist_path):
    """-> list of failure strings across the whole gallery."""
    failures = []
    entries = _entry_index(gallery_json)
    highlights_dir = os.path.join(gallery_dir, "highlights")

    on_disk = set()
    if os.path.isdir(highlights_dir):
        for name in sorted(os.listdir(highlights_dir)):
            if name.endswith(".json"):
                on_disk.add(os.path.join(highlights_dir, name))

    paired_entries = []
    for entry in entries:
        has_url = "highlight_url" in entry
        has_sha = "highlight_sha256" in entry
        if has_url != has_sha:
            failures.append(
                f"highlight: pairing — id={entry.get('id')} declares "
                f"{'highlight_url' if has_url else 'highlight_sha256'} without its "
                "partner; both-or-neither (ADR-029 Decision 4)")
            continue
        if not has_url:
            continue
        # `has()` is true for an explicit JSON null too — a hand-edited index
        # (exactly what this script polices) must fail with a named entry,
        # not a TypeError traceback from os.path.basename(None).
        if not isinstance(entry.get("highlight_url"), str) \
                or not isinstance(entry.get("highlight_sha256"), str) \
                or not isinstance(entry.get("yaml_url"), str):
            failures.append(
                f"highlight: schema — id={entry.get('id')} highlight_url / "
                "highlight_sha256 / yaml_url must all be strings")
            continue
        paired_entries.append(entry)

    if not paired_entries and not on_disk:
        return failures

    if not os.path.isfile(blocklist_path):
        failures.append(
            "highlight: blocklist — ContentBlocklist.json not found at "
            f"{blocklist_path}; the publish-time audit cannot run")
        return failures
    blocklist = load_blocklist(blocklist_path)

    referenced = set()
    for entry in paired_entries:
        entry_id = entry.get("id")
        path = os.path.join(highlights_dir, os.path.basename(entry["highlight_url"]))
        referenced.add(path)
        where = f"[{os.path.relpath(path, os.path.dirname(gallery_dir))}]"
        if not os.path.isfile(path):
            failures.append(
                f"highlight: missing file — id={entry_id} declares highlight_url="
                f"{entry['highlight_url']} but {path} does not exist")
            continue
        actual = sha256_file(path)
        if actual != entry.get("highlight_sha256"):
            failures.append(
                f"highlight: highlight_sha256 mismatch — id={entry_id} "
                f"gallery.json={entry.get('highlight_sha256')} but actual={actual} "
                f"({path})")
        try:
            with open(path, encoding="utf-8") as f:
                doc = json.load(f)
        except (ValueError, UnicodeDecodeError) as exc:
            failures.append(f"highlight: schema — {where} is not valid JSON: {exc}")
            continue
        if not isinstance(doc, dict):
            failures.append(f"highlight: schema — {where} must be a JSON object")
            continue

        stem = os.path.basename(path)[: -len(".json")]
        if stem != entry_id:
            failures.append(
                f"highlight: schema — {where} filename stem {stem!r} != gallery.json "
                f"id {entry_id!r}")
        ref = doc.get("scenario_ref")
        if isinstance(ref, dict) and ref.get("id") != entry_id:
            failures.append(
                f"highlight: schema — {where} scenario_ref.id={ref.get('id')!r} != "
                f"gallery.json id {entry_id!r}")

        yaml_path = os.path.join(gallery_dir, os.path.basename(entry.get("yaml_url", "")))
        if not os.path.isfile(yaml_path):
            failures.append(
                f"highlight: yaml_sha256 mismatch — id={entry_id} sibling YAML "
                f"{yaml_path} is missing, so the pin cannot be verified")
        else:
            yaml_sha = sha256_file(yaml_path)
            ref_sha = ref.get("yaml_sha256") if isinstance(ref, dict) else None
            if ref_sha != entry.get("yaml_sha256") or ref_sha != yaml_sha:
                failures.append(
                    f"highlight: yaml_sha256 mismatch — id={entry_id} highlight pins "
                    f"{ref_sha}, gallery.json has {entry.get('yaml_sha256')}, actual "
                    f"YAML bytes hash to {yaml_sha}. Regenerate or delete the highlight "
                    "(ADR-029 Decision 1: highlights are pinned snapshots)")

        failures += check_content(doc, entry, blocklist, where)

    for path in sorted(on_disk - referenced):
        rel = os.path.relpath(path, os.path.dirname(gallery_dir))
        failures.append(
            f"highlight: orphan — {rel} is not referenced by a gallery.json entry "
            "carrying both highlight_url and highlight_sha256 (the id may be absent "
            "from the index, or present without the fields)")

    return failures


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gallery-json", required=True)
    ap.add_argument("--gallery-dir", required=True)
    ap.add_argument("--blocklist", required=True)
    a = ap.parse_args()

    failures = validate_repo(a.gallery_json, a.gallery_dir, a.blocklist)
    for line in failures:
        print(line)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
