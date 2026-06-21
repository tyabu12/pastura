#!/usr/bin/env python3
"""Select which existing scenarios to evaluate this /scenario-refine cycle.

Enumerates the shipped inventory — bundled presets (`Resources/Presets/`) and
the shared-scenario gallery (`docs/gallery/`) — joins it with the local audit
journal to find each scenario's last-evaluated date, and emits the N
least-recently-evaluated as a ROTATION. Running the whole inventory every
night is too slow (≈45-90 min for all ~21), so each cycle re-checks the
oldest slice; over several nights every scenario comes round again.

Also resolves each scenario's rubric category so the judge knows which 4th
axis to score (the common axes coherence / interaction / breakdown_free apply
to every category — only the 4th differs).

ja/en handling: presets ship ja+en pairs; the gallery is ja-only today (en
siblings land later, ADR-010 Step D). Pairing keys on the YAML `language:`
field, NOT the `_en` filename suffix. ja (and any non-en) primaries are
selected first; en siblings are only reached once the primaries are all
recently evaluated — i.e. en is sampled, not skipped.

usage:
  select_inventory.py [--count N] [--model M]
                      [--presets-dir DIR] [--gallery-dir DIR]
                      [--gallery-json FILE] [--journal FILE]

Output: a JSON array on stdout, highest-priority (least-recently-evaluated)
first:
  [{"id", "name", "path", "channel", "language", "category",
    "payoff_axis", "last_evaluated"}]

This script is READ-ONLY by design — it never writes anything. The skill's
hard safety boundary is that the ONLY writes happen under data/factory/
(harness run logs, A/B candidate YAMLs, the journal); enumeration must never
touch Resources/Presets/ or docs/gallery/.
"""

import argparse
import glob
import json
import os
import re
import sys

# Presets carry no `category` field (that is a gallery.json concept), so they
# need an explicit map. base id = the YAML `id` with a trailing `_en` stripped
# (category is language-independent; the en/ja split is handled separately via
# the `language:` field). Keep in sync with Resources/Presets/.
PRESET_CATEGORY = {
    "bokete": "creative",
    "prisoners_dilemma": "game_theory",
    "target_score_race": "game_theory",
    "word_wolf": "game_theory",
}

# category → the 4th rubric axis the judge scores (axes a/b/c are universal).
CATEGORY_AXIS = {
    "creative": "humor",
    "game_theory": "strategic_tension",
    "ethics": "moral_divergence",
    "social_psychology": "phenomenon_visible",
    "roleplay": "narrative_engagement",
}
# experimental / unknown / absent category → a generic engagement axis so a
# future gallery entry under an unmapped category never KeyErrors.
FALLBACK_AXIS = "overall_engagement"
FALLBACK_CATEGORY = "experimental"


def payoff_axis(category):
    return CATEGORY_AXIS.get(category, FALLBACK_AXIS)


def yaml_scalar(path, field):
    """Read a top-level scalar `field:` from a Pastura scenario YAML.

    Line-based on purpose — the harness owns full YAML parsing; here we only
    need a couple of top-level scalars (id / name / language), so we avoid a
    PyYAML dependency the rest of the skill toolchain does not carry.
    """
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(rf"\s*{re.escape(field)}:\s*(.+?)\s*$", line)
                if m and not line.startswith(" "):  # top-level key only
                    return m.group(1).strip().strip('"').strip("'")
    except OSError:
        return None
    return None


def base_id(scenario_id):
    return re.sub(r"_en$", "", scenario_id or "")


def enumerate_presets(presets_dir):
    items = []
    for path in sorted(glob.glob(os.path.join(presets_dir, "*.yaml"))):
        stem = os.path.splitext(os.path.basename(path))[0]
        sid = yaml_scalar(path, "id") or stem
        category = PRESET_CATEGORY.get(base_id(sid), FALLBACK_CATEGORY)
        items.append({
            "id": sid,
            "name": yaml_scalar(path, "name") or sid,
            "path": path,
            "channel": "preset",
            "language": yaml_scalar(path, "language") or "ja",
            "category": category,
            "payoff_axis": payoff_axis(category),
        })
    return items


def enumerate_gallery(gallery_dir, gallery_json):
    items = []
    if not os.path.exists(gallery_json):
        return items
    with open(gallery_json, encoding="utf-8") as f:
        index = json.load(f)
    for entry in index.get("scenarios", []):
        sid = entry.get("id")
        if not sid:
            continue  # malformed gallery.json entry — never emit a null-id item
        url = entry.get("yaml_url", "")
        # gallery.json yaml_url is a bare filename resolved relative to the
        # index; an absolute https URL has no local file to run, so skip it.
        if url.startswith("http"):
            continue
        path = os.path.join(gallery_dir, url)
        category = entry.get("category") or FALLBACK_CATEGORY
        items.append({
            "id": sid,
            "name": entry.get("title") or entry.get("id"),
            "path": path,
            "channel": "gallery",
            "language": yaml_scalar(path, "language") or "ja",
            "category": category,
            "payoff_axis": payoff_axis(category),
        })
    return items


# Each /scenario-refine section embeds one machine-readable data comment (see
# append_audit.py) carrying that night's per-scenario scores. Parsing it — not
# the human table — is the robust way to learn when each scenario was last
# evaluated (and, in append_audit, its prior scores for the baseline delta).
# Must stay byte-identical to append_audit.py's copy — the reader and writer
# of the same audit-data contract. Change both or neither.
AUDIT_DATA_RE = re.compile(r"<!--\s*audit-data:\s*(\{.*?\})\s*-->")


def parse_journal_last_evaluated(journal, model):
    """Map scenario id → most-recent date it was evaluated with `model`.

    A missing / unparseable journal yields an empty map (first-run path:
    every scenario then reads as never-evaluated = highest rotation
    priority). Only entries whose model matches count, so a model swap
    re-evaluates the inventory from scratch.
    """
    last = {}
    if not journal or not os.path.exists(journal):
        return last
    try:
        with open(journal, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return last
    for blob in AUDIT_DATA_RE.findall(text):
        try:
            data = json.loads(blob)
        except json.JSONDecodeError:
            continue
        if model is not None and data.get("model") != model:
            continue
        date = data.get("date", "")
        for sid in (data.get("scenarios") or {}):
            if date > last.get(sid, ""):
                last[sid] = date
    return last


def select(items, last_evaluated, count):
    """Rotation: least-recently-evaluated first, ja/non-en before en.

    A never-evaluated scenario sorts as oldest (epoch "" < any date). en
    siblings form a lower-priority tier so they are reached only when the
    primaries are all recently evaluated — sampling rather than skipping.
    """
    for it in items:
        it["last_evaluated"] = last_evaluated.get(it["id"]) or None

    def sort_key(it):
        return (it["last_evaluated"] or "", it["id"])

    primary = sorted((i for i in items if i["language"] != "en"), key=sort_key)
    secondary = sorted((i for i in items if i["language"] == "en"), key=sort_key)
    return (primary + secondary)[:count]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--model", default="gemma-4-E2B-it-Q4_K_M")
    parser.add_argument("--presets-dir",
                        default="Pastura/Pastura/Resources/Presets")
    parser.add_argument("--gallery-dir", default="docs/gallery")
    parser.add_argument("--gallery-json", default="docs/gallery/gallery.json")
    parser.add_argument("--journal", default="data/factory/audit-digest.md")
    args = parser.parse_args()

    items = (enumerate_presets(args.presets_dir)
             + enumerate_gallery(args.gallery_dir, args.gallery_json))
    last = parse_journal_last_evaluated(args.journal, args.model)
    selected = select(items, last, args.count)
    json.dump(selected, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
