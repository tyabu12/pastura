#!/usr/bin/env python3
"""Gallery novelty census — rank under-represented scenario formats & categories.

usage: gallery_census.py [path/to/gallery.json]   (default: docs/gallery/gallery.json)

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

import json
import sys

# Structural novelty axes: (label, predicate over the phase-type set). The
# scaffolding phases (assign / summarize / speak_all) are deliberately NOT axes
# — they don't define a scenario's format. List order is the deterministic
# tie-break for equally-rare axes (a stable sort on count preserves it).
AXES = [
    ("peer_vote", lambda p: "vote" in p),
    ("scored", lambda p: "score_calc" in p),
    ("decision", lambda p: "choose" in p),
    ("elimination", lambda p: "eliminate" in p),
    ("branching", lambda p: "conditional" in p),
    ("reactive_event", lambda p: "event_inject" in p),
    ("sequential_build", lambda p: "speak_each" in p),
    ("scoring_free", lambda p: "vote" not in p and "score_calc" not in p),
]

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


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "docs/gallery/gallery.json"
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
    cat_counts = {c: 0 for c in VALID_CATEGORIES}
    for s in scenarios:
        cat = s.get("category")
        if cat:
            cat_counts[cat] = cat_counts.get(cat, 0) + 1
    n_cat = sum(1 for s in scenarios if s.get("category"))
    cats_by_presence = sorted(cat_counts.items(), key=lambda x: (x[1], x[0]))

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
    print()
    print("Assign each of the 3 generated scenarios a DISTINCT axis from the rare end.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
