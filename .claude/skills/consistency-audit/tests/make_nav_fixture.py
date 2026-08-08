#!/usr/bin/env python3
"""Materialize the adr_navigation_missing fixture repo into a target directory.

Generated rather than committed, for a reason that is itself the point of the
arms: every arm except ADR-103 has to clear NAV_MIN_LINES (600), so that a
silent one is silent because of the *counting* rule it tests and not because it
is short. (ADR-103 is the deliberate exception — it is the arm that tests the
size gate, so being short is what it exercises.) A control that cannot redden is
measuring nothing. Those eleven arms are ~7300 lines of filler; the arm table
below IS the fixture, and the filler is noise materialized on demand.

Emits a JSON manifest on stdout: {"ADR-NNN": {"total_lines": N}, ...}. The
harness asserts every must-not-fire arm cleared the size gate, which is what
stops a drifting generator from turning an arm into a false green.

usage: make_nav_fixture.py <dir>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

FILLER = ("Filler prose that carries no ADR reference and no heading, so it "
          "contributes only to the line count.")


def section(heading: str, n: int) -> list[str]:
    return [heading, ""] + [FILLER] * n + [""]


def fenced_section(heading: str, n: int, buried: str) -> list[str]:
    """A section whose filler wraps a fenced block containing `buried` — the
    shape that must not be read as structure."""
    return ([heading, "", "```markdown", buried, "```", ""]
            + [FILLER] * n + [""])


# (nnn, title, body_lines, extra) — `extra` returns the lines after the intro.
ARMS: dict[str, tuple[str, list[str]]] = {
    # FIRES: plain capital `## Amendment <date>`. Doubles as the re.I control —
    # without the flag `\bamendments?\b` cannot match "Amendment", this arm
    # stops firing, and the expected-count assertion reddens.
    "101": ("plain amendment heading, over both thresholds, no map",
            section("## Context", 250) + section("## Amendment 2026-01-01 — settled", 400)),
    # Silent: the navigation section discharges it (the ADR-028 shape).
    "102": ("same bulk, but carries a navigation section",
            section("## How to read this ADR", 20) + section("## Context", 250)
            + section("## Amendment 2026-01-01 — settled", 400)),
    # Silent: under the size gate. Share is 66%, so only size can be silencing it.
    "103": ("high share but small — under the size gate",
            section("## Context", 100) + section("## Amendment 2026-01-01 — settled", 200)),
    # Silent: over the size gate, under the share gate. The second threshold
    # needs its own arm — arm 103 cannot exercise it.
    "104": ("large but body-dominated — under the share gate",
            section("## Context", 600) + section("## Amendment 2026-01-01 — settled", 100)),
    # Silent: the opt-out marker.
    "105": ("would fire, but carries the nav-exempt marker",
            ["<!-- nav-exempt: short enough to hold in one read -->", ""]
            + section("## Context", 250)
            + section("## Amendment 2026-01-01 — settled", 400)),
    # Silent under per-section spans, FIRES under first-amendment-to-EOF. The
    # two measures land on opposite sides of the gate by construction, so this
    # arm is what catches an EOF-measuring implementation.
    "106": ("body section AFTER an amendment — span-sum vs EOF control",
            section("## Context", 40) + section("## Amendment 2026-01-01 — settled", 180)
            + section("## Consequences", 450)),
    # FIRES: mentions the opt-out inside an inline code span, the natural way to
    # write about it in prose. A substring search would let a document that
    # merely *discusses* the marker exempt itself; fence-skipping does not cover
    # this, because an inline span is not a fence.
    "111": ("mentions the nav-exempt marker in prose, without adopting it",
            ["An ADR opts out by putting `<!-- nav-exempt: reason -->` on its "
             "own line.", ""]
            + section("## Context", 250)
            + section("## Amendment 2026-01-01 — settled", 400)),
    # FIRES: shows the marker as a 4-space indented code block, the other way
    # to write an example. FENCE_DELIM only recognises ``` / ~~~, so nothing
    # strips it — the column-0 anchor is the only thing keeping this file from
    # exempting itself.
    "112": ("shows the nav-exempt marker as an indented code block",
            ["An ADR opts out like this:", "",
             "    <!-- nav-exempt: reason -->", ""]
            + section("## Context", 250)
            + section("## Amendment 2026-01-01 — settled", 400)),
    # Silent: `###` is not a top-level heading, so it is not a section boundary.
    "107": ("amendment recorded at ### level only",
            section("## Context", 250) + section("### Amendment 2026-01-01 — settled", 400)),
    # Silent: inline bold is not a heading. This is a real ADR's convention in
    # this repo, and the permanent false-negative class the module docstring
    # records. The arm title carries no `ADR-NNN` token — a reference to a
    # fileless ADR would fire dangling_adr and contaminate this fixture.
    "108": ("amendment recorded as inline bold only",
            section("## Context", 250)
            + ["## Notes", "", "**Amendment 2026-01-01:** recorded inline.", ""]
            + [FILLER] * 400 + [""]),
    # Silent: a heading-shaped line inside a fence is illustration.
    "109": ("`## Amendment` appears only inside a fenced block",
            section("## Context", 250)
            + fenced_section("## Notes", 400, "## Amendment 2026-01-01 — an example")),
    # FIRES: the numbered + lowercase-suffix shape (ADR-002 §10–13) and the
    # `## N. Amendments` shape (ADR-005). Both must count, and both must be
    # reported as numbered so the finding's counter-evidence is accurate.
    "110": ("numbered and lowercase-suffix amendment shapes",
            section("## Context", 120)
            + section("## 10. Streaming Extension (2026-01-01 amendment)", 300)
            + section("## 11. Amendments", 200)),
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(sys.argv[1])
    adr_dir = root / "docs" / "decisions"
    adr_dir.mkdir(parents=True, exist_ok=True)

    manifest: dict[str, dict] = {}
    index = ["# Decision records", ""]
    for nnn, (title, extra) in sorted(ARMS.items()):
        lines = [f"# ADR-{nnn} — {title}", ""] + extra
        (adr_dir / f"ADR-{nnn}.md").write_text("\n".join(lines) + "\n",
                                               encoding="utf-8")
        manifest[f"ADR-{nnn}"] = {"total_lines": len(lines)}
        index.append(f"## ADR-{nnn} — {title}")
        index.append("")
    (adr_dir / "INDEX.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    # No "ADR roster" line: roster_findings only probes a CLAUDE.md that
    # declares one, so omitting it keeps this fixture scoped to one detector.
    (root / "CLAUDE.md").write_text(
        "# adr_navigation_missing fixture\n\n"
        "Twelve arms; four must fire (ADR-101, ADR-110, ADR-111, ADR-112) and "
        "eight must stay silent, each for its own stated reason.\n",
        encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
