#!/usr/bin/env python3
"""Negative controls for adr_navigation_missing: one mutation per guard.

The fixture arms in make_nav_fixture.py are silent by design, and a silent arm
proves nothing on its own — a guard's success case never demonstrates the guard
exists. Each mutation below disables exactly one guard and asserts the arm that
claims to defend against it flips. An arm with no mutation here is an untested
arm, so every arm has one.

Two things this checks that a naive mutation harness does not:

  * **The anchor matched.** A `str.replace` that finds nothing leaves the
    original behaviour and reads as a passing control.
  * **Collateral is declared, not ignored.** A second arm that also depends on
    the mutated guard is real coupling and is listed; an *undeclared* flip means
    the arm is not keyed to this guard alone and would redden for the wrong
    reason.

Two arms took more than one attempt to key correctly, which is why the harness
is committed rather than run once by hand: `###` exclusion turned out to be
defended by *both* heading anchors (widening either alone is a no-op), and the
first `###` mutation targeted the classifier when the collection filter was
doing the work.

usage: mutate_nav_guards.py [workdir]   (cwd must be this tests/ directory)
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SRC = Path("../scripts/audit_docs.py")
GEN = Path("make_nav_fixture.py")

AMD_DECL = (r'AMENDMENT_HEADING = re.compile('
            r'r"^## +(?:\d+\.\s*)?.*\bamendments?\b", re.I)')
H2_DECL = 'H2_HEADING = re.compile(r"^## ")'

# (name, replacements, arm, expectation, declared_collateral)
MUTATIONS: list[tuple] = [
    ("drop re.I on AMENDMENT_HEADING",
     [(AMD_DECL, AMD_DECL.replace(", re.I", ""))],
     "ADR-101", "stops",
     # 110's `## 11. Amendments` needs the flag too; without it 110 keeps only
     # its lowercase-suffix section and falls to 47.9%, under the share gate.
     {"ADR-110"}),
    ("measure first-amendment-to-EOF instead of per-section spans",
     [("            end = headings[k + 1][0] if k + 1 < len(headings) else total",
       "            end = total")],
     "ADR-106", "starts", set()),
    ("widen both heading anchors to ###",
     [(H2_DECL, 'H2_HEADING = re.compile(r"^#{2,3} ")'),
      ('AMENDMENT_HEADING = re.compile(r"^## +',
       'AMENDMENT_HEADING = re.compile(r"^#{2,3} +')],
     "ADR-107", "starts", set()),
    ("count inline-bold markers as amendment headings",
     [(H2_DECL, 'H2_HEADING = re.compile(r"^(?:## |\\*\\*Amendment)")'),
      (AMD_DECL, r'AMENDMENT_HEADING = re.compile('
                 r'r"^(?:## +(?:\d+\.\s*)?|\*\*).*\bamendments?\b", re.I)')],
     "ADR-108", "starts", set()),
    # The narrowing this detector considered and declined: it silences the
    # numbered / lowercase-suffix shape, so ADR-110 records the *choice*, not
    # merely the behaviour.
    ("narrow to headings that START with Amendment",
     [(AMD_DECL, r'AMENDMENT_HEADING = re.compile('
                 r'r"^## +(?:\d+\.\s*)?Amendments?\b", re.I)')],
     "ADR-110", "stops", set()),
    ("drop the fence skip",
     [("            if in_fence:\n                continue\n            bare.append(line)",
       "            if False:\n                continue\n            bare.append(line)")],
     "ADR-109", "starts", set()),
    ("drop the nav-exempt opt-out",
     [("        if any(NAV_EXEMPT.search(line) for line in bare):\n            continue",
       "        if False:\n            continue")],
     "ADR-105", "starts", set()),
    ("drop the navigation-section check",
     [("        if any(NAV_HEADING.match(line) for _, line in headings):\n            continue",
       "        if False:\n            continue")],
     "ADR-102", "starts", set()),
    ("drop the size gate",
     [("        if total < NAV_MIN_LINES:\n            continue",
       "        if False:\n            continue")],
     "ADR-103", "starts", set()),
    ("drop the share gate",
     [("        if not sections or amendment_lines < total * NAV_MIN_SHARE:",
       "        if not sections or False:")],
     "ADR-104", "starts",
     # 106 is silent *because of* the share gate (span-sum share 26.7%).
     {"ADR-106"}),
]

BASELINE = {"ADR-101", "ADR-110"}


def fired(script: Path, fixdir: Path) -> set[str]:
    shutil.rmtree(fixdir, ignore_errors=True)
    subprocess.run([sys.executable, str(GEN), str(fixdir)], check=True,
                   stdout=subprocess.DEVNULL)
    out = subprocess.run([sys.executable, str(script), "--repo-root", str(fixdir)],
                         capture_output=True, text=True, check=True).stdout
    return {f["adr"] for f in json.loads(out)["needs_judgment"]
            if f["type"] == "adr_navigation_missing"}


def main() -> int:
    orig = SRC.read_text(encoding="utf-8")
    ok = True
    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        fixdir = work / "fix"
        base = fired(SRC, fixdir)
        if base != BASELINE:
            print(f"FAIL: baseline fires {sorted(base)}, expected "
                  f"{sorted(BASELINE)}", file=sys.stderr)
            return 1
        mutant = work / "mutant.py"
        for name, pairs, arm, expect, collateral in MUTATIONS:
            if any(old not in orig for old, _ in pairs):
                print(f"FAIL: anchor miss for {name!r} — the mutation would "
                      f"no-op and the control would pass vacuously",
                      file=sys.stderr)
                ok = False
                continue
            text = orig
            for old, new in pairs:
                text = text.replace(old, new, 1)
            mutant.write_text(text, encoding="utf-8")
            got = fired(mutant, fixdir)
            flipped = (arm in base and arm not in got) if expect == "stops" \
                else (arm not in base and arm in got)
            undeclared = (got ^ base) - {arm} - collateral
            if flipped and not undeclared:
                print(f"  ok   {arm} {expect:<6} <- {name}")
            else:
                ok = False
                print(f"  FAIL {arm} {expect:<6} <- {name}: got {sorted(got)}"
                      + (f", undeclared collateral {sorted(undeclared)}"
                         if undeclared else ""), file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
