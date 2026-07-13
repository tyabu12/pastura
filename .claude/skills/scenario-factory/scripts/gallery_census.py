#!/usr/bin/env python3
"""Gallery novelty census — rank under-represented scenario formats & categories.

usage: gallery_census.py [path/to/gallery.json] [--phase-types path/to/PhaseType.swift]
       (defaults: docs/gallery/gallery.json, Pastura/Pastura/Models/PhaseType.swift)

Reads the shared-scenario gallery and reports, deterministically, which
STRUCTURAL MECHANIC AXES and CATEGORIES are under-represented, so a
/scenario-factory cycle steers generation toward the gaps instead of piling
onto the crowded vote->score_calc majority.

The census measures phase-TYPE presence (does this scenario contain a `vote`
phase at all?), NOT mechanical depth (vote_tally vs other score_calc logic,
conditional branch structure). It is gallery-only and fully deterministic —
cross-night axis rotation is an in-session reasoning step in SKILL.md Step 1.5,
not handled here.

Exit 0 always (an empty/unreadable gallery prints a notice, never crashes the
overnight cycle).
"""

import argparse
import json
import re
import sys

# Structural novelty axes: (label, predicate over the phase-type set). The
# scaffolding phases (assign / summarize / speak_all) are deliberately NOT axes
# — they don't define a scenario's format. List order is the deterministic
# tie-break for equally-rare axes (a stable sort on count preserves it).
# NOTE: `scoring_free` is a NEGATION axis — a scenario counts toward it
# precisely because it lacks vote AND score_calc, so it is anti-correlated
# with peer_vote/scored by construction (the axes are not all orthogonal).
AXES = [
    ("peer_vote", lambda p: "vote" in p),
    ("scored", lambda p: "score_calc" in p),
    ("decision", lambda p: "choose" in p),
    ("elimination", lambda p: "eliminate" in p),
    ("branching", lambda p: "conditional" in p),
    ("reactive_event", lambda p: "event_inject" in p),
    ("sequential_build", lambda p: "speak_each" in p),
    ("pair_whisper", lambda p: "whisper" in p),
    ("reflection", lambda p: "reflect" in p),
    ("relationship_memory", lambda p: "relationship_update" in p),
    ("live_narration", lambda p: "narrate" in p),
    ("scoring_free", lambda p: "vote" not in p and "score_calc" not in p),
]

# Phase-type strings the AXES lambdas key on. Lambda bodies can't be
# introspected, so this set is maintained by hand — it MUST be updated
# alongside AXES whenever an axis is added/removed. It powers the PhaseType
# drift tripwire (compute_engine_phases + the NEW-mechanic warning below):
# any Engine phase absent from AXIS_PHASES ∪ SCAFFOLDING_PHASES surfaces as an
# uncovered mechanic. (`scoring_free` is a negation axis over vote/score_calc,
# already listed.)
AXIS_PHASES = {
    "vote", "score_calc", "choose", "eliminate", "conditional",
    "event_inject", "speak_each", "whisper", "reflect", "relationship_update",
    "narrate",
}

# Scaffolding phases deliberately NOT modeled as axes (see the AXES comment):
# they structure a scenario but don't define its format. Listed here so the
# drift tripwire treats them as covered rather than flagging them as new.
SCAFFOLDING_PHASES = {"assign", "summarize", "speak_all"}

# Valid gallery categories — mirror of GalleryCategory in
# Pastura/Pastura/Models/GalleryScenario.swift (snake_case raw values). Kept
# here so the census surfaces ZERO-entry categories (the rarest possible),
# which never appear as keys in gallery.json. Eyeball on a category enum change.
VALID_CATEGORIES = [
    "social_psychology", "game_theory", "ethics",
    "roleplay", "creative", "experimental",
]

RARE_FRAC = 0.25
CROWDED_FRAC = 0.60


def flag(count, n):
    """rare / crowded / "" for a presence count against denominator n."""
    if n == 0:
        return ""
    frac = count / n
    if frac <= RARE_FRAC:
        return "rare"
    if frac >= CROWDED_FRAC:
        return "crowded"
    return ""


def line(label, count, n):
    fl = flag(count, n)
    tag = f"  [{fl}]" if fl else ""
    return f"  {label:<18} {count:>2}/{n}{tag}"


# Matches a Swift enum `case <name>` line, optionally with an explicit raw
# value (`case foo = "bar"`). The leading `case\s+(?![.])` guards against
# switch-statement patterns like `case .speakAll, .futurePhase:` (identifiers
# there are dot-prefixed) and `default:` (no identifier). ASSUMES ONE CASE PER
# LINE, matching the current PhaseType.swift shape: a future comma-joined
# `case a, b` would under-parse (b silently dropped). That direction HIDES a
# phase — an unparsed phase can't trip the NEW-mechanic warning — so if the
# real file ever adopts comma-joined cases this regex must be widened.
_CASE_RE = re.compile(r'^\s*case\s+(?![.])([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*"([^"]+)")?')


def compute_engine_phases(path):
    """Parse PhaseType.swift as TEXT → the set of phase raw-value strings.

    The raw value is the explicit `= "..."` string when present, else the case
    identifier verbatim (Swift's default RawRepresentable value). Returns None
    on any read error so the caller can fail-open and skip the drift check.
    """
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as exc:
        print(f"gallery_census: cannot read {path}: {exc} — "
              "skipping PhaseType drift check", file=sys.stderr)
        return None
    phases = set()
    for raw_line in text.splitlines():
        m = _CASE_RE.match(raw_line)
        if m:
            phases.add(m.group(2) or m.group(1))
    return phases  # already deduped (a set)


def main():
    parser = argparse.ArgumentParser(
        description="Gallery novelty census — rank under-represented formats.")
    parser.add_argument(
        "gallery", nargs="?", default="docs/gallery/gallery.json",
        help="path to gallery.json (default: docs/gallery/gallery.json)")
    parser.add_argument(
        # This default path breaks SILENTLY (fail-open) if Models/ is ever
        # extracted to an SPM package — the repo-root existence assertion in
        # tests/run_tests.sh is the tripwire that catches that move.
        "--phase-types", default="Pastura/Pastura/Models/PhaseType.swift",
        help="path to PhaseType.swift for the drift tripwire")
    args = parser.parse_args()
    path = args.gallery
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"gallery_census: cannot read {path}: {exc}", file=sys.stderr)
        return 0  # never crash the overnight cycle

    scenarios = data.get("scenarios", [])
    total = len(scenarios)
    print(f"=== Gallery novelty census ({total} scenario(s)) ===")
    if total == 0:
        print("  empty gallery — no targets to suggest.")
        return 0

    # Structural axes carry a signal only from scenarios with a non-empty
    # `phases` list. `phases` is [String]? in the schema (nullable for
    # forward-compat), so missing/null/empty entries are excluded from the axis
    # denominator rather than miscounted as scoring_free.
    with_phases = [s for s in scenarios if s.get("phases")]
    n_ax = len(with_phases)
    skipped = total - n_ax
    axis_counts = [
        (label, sum(1 for s in with_phases if pred(set(s["phases"]))))
        for label, pred in AXES
    ]
    by_presence = sorted(axis_counts, key=lambda x: x[1])  # stable → AXES order on ties

    print()
    note = f" — {skipped} skipped: no phases" if skipped else ""
    print(f"Structural axes (presence / {n_ax}){note}:")
    for label, count in by_presence:
        print(line(label, count, n_ax))

    # Categories — seed every valid category at 0 so absent ones still rank.
    # `category` is a non-optional field in the schema, so n_cat == total in
    # practice; the axis denominator (n_ax) may be smaller because it excludes
    # phase-less entries — the two fractions are intentionally not comparable.
    cat_counts = {c: 0 for c in VALID_CATEGORIES}
    for s in scenarios:
        cat = s.get("category")
        if cat:
            cat_counts[cat] = cat_counts.get(cat, 0) + 1
    n_cat = sum(1 for s in scenarios if s.get("category"))
    cats_by_presence = sorted(cat_counts.items(), key=lambda x: (x[1], x[0]))
    # Surface enum drift the hardcoded VALID_CATEGORIES can't anticipate, so a
    # new/typo'd category lands in the overnight log instead of silently
    # inflating the denominator.
    unknown = sorted(c for c in cat_counts if c not in VALID_CATEGORIES)
    if unknown:
        print("census: WARNING unrecognized categories (GalleryCategory "
              f"drift?): {', '.join(unknown)}", file=sys.stderr)

    print()
    print(f"Category (count / {n_cat}):")
    for cat, count in cats_by_presence:
        print(line(cat, count, n_cat))

    # Suggested targets — the rare end; fall back to the 3 rarest if nothing
    # trips the threshold so a batch always has gap targets to assign.
    rare_axes = [lab for lab, c in by_presence if flag(c, n_ax) == "rare"]
    mech_targets = rare_axes or [lab for lab, _ in by_presence[:3]]
    crowded_axes = [lab for lab, c in by_presence if flag(c, n_ax) == "crowded"]
    rare_cats = [cat for cat, c in cats_by_presence if flag(c, n_cat) == "rare"]
    cat_targets = rare_cats or [cat for cat, _ in cats_by_presence[:3]]

    print()
    print("=== Suggested targets for this batch (favor the rare end) ===")
    print(f"  mechanic axes: {', '.join(mech_targets) or '(none)'}")
    print(f"  categories:    {', '.join(cat_targets) or '(none)'}")
    if crowded_axes:
        print(f"  avoid piling onto crowded axes: {', '.join(crowded_axes)}")

    # PhaseType drift tripwire — surface Engine phases that shipped without a
    # census axis, so a future phase becomes a MAXIMAL-RARITY target instead of
    # going unnoticed. Fail-open: unreadable/missing file skips silently (a
    # stderr notice is printed inside compute_engine_phases), mirroring the
    # gallery-read fail-open above — never crash the overnight cycle.
    engine_phases = compute_engine_phases(args.phase_types)
    if engine_phases is not None:
        uncovered = engine_phases - AXIS_PHASES - SCAFFOLDING_PHASES
        if uncovered:
            print()
            print("⚠️ NEW ENGINE MECHANICS not yet in the census axes: "
                  f"{', '.join(sorted(uncovered))}")
            print("   Treat these as MAXIMAL-RARITY targets. Before authoring, read")
            print("   Pastura/Pastura/Engine/Phases/<X>Handler.swift and tracking issue #906.")

    print()
    print("Assign each of the 3 generated scenarios a DISTINCT axis from the rare end.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
