#!/usr/bin/env python3
"""Mechanically-verifiable documentation / ADR consistency detector.

Read-only by default: prints a JSON report of inconsistencies and exits.
Nothing is written and no PR/issue is created — that is the consistency-audit
SKILL's job, which consumes this JSON. This separation keeps detection
deterministic and testable, and makes "dry-run" the default by construction.

Two finding classes:

  auto_fixable   — the correct value is uniquely determined by an authoritative
                   source (Package.resolved, project.pbxproj). Safe to rewrite
                   mechanically; `--fix` applies exactly these edits in place.
  needs_judgment — detected mechanically, but the fix needs human judgment
                   (which target did a dead link mean?). Never auto-applied;
                   the SKILL files an issue with a confidence + counter-evidence
                   section.

Conservatism is deliberate: false positives poison the queue, so each detector
prefers a miss over a wrong flag. v1 ships only the three detectors proven to
fire zero false positives on the current repo (dependency_version, min_ios,
dead_link). Detectors that flood until their FP sources are designed out are
intentionally deferred — see the SKILL's "Deferred detectors" note:
  - file:line citation checks   (docs cite source-root-relative paths, GitHub
                                 org/repo slugs, and property accessors that a
                                 naive repo-root existence check misreads)
  - ADR-missing reference checks (reserved/not-yet-written ADRs like ADR-006
                                 are referenced from lines without the marker)
  - broken-anchor / `§"..."`    (fragile GitHub-slug matching; ambiguous target)

usage:
  audit_docs.py [--repo-root DIR] [--fix]
                [--package-resolved PATH] [--pbxproj PATH]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Authoritative-source default locations (relative to the repo root). The
# xcodeproj's resolved file is the one Xcode actually builds against.
DEFAULT_RESOLVED = (
    "Pastura/Pastura.xcodeproj/project.xcworkspace/"
    "xcshareddata/swiftpm/Package.resolved"
)
DEFAULT_PBXPROJ = "Pastura/Pastura.xcodeproj/project.pbxproj"

# Dependencies we mirror in docs, keyed by the Package.resolved `identity`.
# GRDB's identity is `grdb.swift` (not `grdb`); matching by identity — and
# reading `version`, never `revision` — avoids picking up a transitive pin or
# substituting a 40-char git SHA into the docs.
DEP_TOKENS = [("Yams", "yams"), ("GRDB", "grdb.swift")]

SEMVER = re.compile(r"\b\d+\.\d+\.\d+\b")
IOS_VER = re.compile(r"\b\d+\.\d+\b")
MINIOS_LABEL = re.compile(r"(?i)min(?:imum)?\s+ios")
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
RESERVED = re.compile(r"(?i)reserved|not[\s-]?yet[\s-]?written")
FENCE = re.compile(r"^\s*(```|~~~)")

EXCLUDE_PARTS = {".git", "DerivedData", "node_modules"}


def excluded(relpath: str) -> bool:
    rp = relpath.replace(os.sep, "/")
    if any(p in EXCLUDE_PARTS for p in rp.split("/")):
        return True
    # Never scan the audit's own fixtures or sibling worktrees.
    if "tests/fixtures/" in rp + "/" or rp.startswith("tests/fixtures/"):
        return True
    if rp.startswith(".claude/worktrees/") or "/.claude/worktrees/" in "/" + rp:
        return True
    return False


def discover_docs(root: Path) -> list[Path]:
    docs: list[Path] = []
    for name in ("CLAUDE.md", "README.md", "CONTRIBUTING.md"):
        p = root / name
        if p.is_file():
            docs.append(p)
    for base in ("docs", ".claude/rules"):
        bp = root / base
        if bp.is_dir():
            docs.extend(sorted(bp.rglob("*.md")))
    return [p for p in docs if not excluded(os.path.relpath(p, root))]


def load_resolved(path: Path) -> dict[str, str]:
    """identity -> version, for our mirrored deps only. Reads `version`,
    never `revision`."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    out: dict[str, str] = {}
    wanted = {ident for _, ident in DEP_TOKENS}
    for pin in data.get("pins", []):
        ident = pin.get("identity")
        if ident in wanted:
            ver = pin.get("state", {}).get("version")
            if ver:
                out[ident] = ver
    return out


def load_min_ios(path: Path) -> str | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    vals = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([0-9.]+)", text))
    return vals.pop() if len(vals) == 1 else None


def scan_doc(path: Path, root: Path, resolved: dict[str, str],
             min_ios: str | None):
    """Return (auto_fixable, judgment) finding lists for one doc file."""
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return [], []
    auto: list[dict] = []
    judg: list[dict] = []
    doc_dir = path.parent
    in_fence = False

    for lineno, line in enumerate(lines, 1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

        # --- auto_fixable: dependency version drift ---
        for display, ident in DEP_TOKENS:
            if ident not in resolved:
                continue
            if not re.search(r"\b" + re.escape(display) + r"\b", line):
                continue
            semvers = SEMVER.findall(line)
            if len(semvers) != 1:  # 0 = no claim, >1 = ambiguous -> skip
                continue
            if semvers[0] != resolved[ident]:
                auto.append({
                    "type": "dependency_version",
                    "file": rel, "line": lineno,
                    "dependency": display,
                    "current": semvers[0], "expected": resolved[ident],
                    "authoritative_source": "Package.resolved",
                })

        # --- auto_fixable: minimum-iOS drift ---
        if min_ios and MINIOS_LABEL.search(line):
            vers = IOS_VER.findall(line)
            if len(vers) == 1 and vers[0] != min_ios:
                auto.append({
                    "type": "min_ios",
                    "file": rel, "line": lineno,
                    "current": vers[0], "expected": min_ios,
                    "authoritative_source": "project.pbxproj",
                })

        # A line carrying a "reserved / not yet written" marker describes an
        # intentionally-absent target (e.g. the ADR-006 reservation row), so
        # missing-target detectors must skip it.
        if RESERVED.search(line):
            continue

        # --- needs_judgment: dead relative .md links ---
        for m in MD_LINK.finditer(line):
            raw = m.group(1).strip()
            url = raw.split()[0] if raw else ""  # drop optional "title"
            target = url.split("#", 1)[0]
            if not target:
                continue  # pure #anchor -> deferred broken_anchor detector
            low = target.lower()
            if low.startswith(("http://", "https://", "mailto:", "tel:",
                               "//", "/", "#")):
                continue
            if not low.endswith(".md"):
                continue  # v1 scope: doc-to-doc links only
            tgt = (doc_dir / target).resolve()
            if not tgt.exists():
                judg.append({"type": "dead_link", "target": target,
                             "key": str(tgt), "file": rel, "line": lineno})

    return auto, judg


def dedup_judgment(items: list[dict]) -> list[dict]:
    """Collapse by (type, key) so one broken target is one finding with all
    its locations — one issue per distinct problem, not per occurrence."""
    grouped: dict[tuple[str, str], dict] = {}
    for it in items:
        gk = (it["type"], it["key"])
        g = grouped.setdefault(gk, {
            "type": it["type"], "target": it["target"], "locations": []})
        g["locations"].append({"file": it["file"], "line": it["line"]})
    return list(grouped.values())


def apply_fixes(root: Path, fixes: list[dict]) -> None:
    by_file: dict[str, list[dict]] = {}
    for f in fixes:
        by_file.setdefault(f["file"], []).append(f)
    for rel, items in by_file.items():
        p = root / rel
        lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
        for it in items:
            idx = it["line"] - 1
            if 0 <= idx < len(lines):
                lines[idx] = lines[idx].replace(
                    it["current"], it["expected"], 1)
        p.write_text("".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo-root", default=None)
    ap.add_argument("--package-resolved", default=None)
    ap.add_argument("--pbxproj", default=None)
    ap.add_argument("--fix", action="store_true",
                    help="apply auto_fixable version-string edits in place")
    args = ap.parse_args()

    if args.repo_root:
        root = Path(args.repo_root).resolve()
    else:
        try:
            root = Path(subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                text=True).strip()).resolve()
        except (subprocess.CalledProcessError, OSError):
            print("error: not in a git repo; pass --repo-root", file=sys.stderr)
            return 2

    resolved_path = (Path(args.package_resolved) if args.package_resolved
                     else root / DEFAULT_RESOLVED)
    pbxproj_path = (Path(args.pbxproj) if args.pbxproj
                    else root / DEFAULT_PBXPROJ)
    resolved = load_resolved(resolved_path)
    min_ios = load_min_ios(pbxproj_path)

    auto: list[dict] = []
    judg: list[dict] = []
    for doc in discover_docs(root):
        a, j = scan_doc(doc, root, resolved, min_ios)
        auto.extend(a)
        judg.extend(j)

    if args.fix and auto:
        apply_fixes(root, auto)

    report = {
        "auto_fixable": auto,
        "needs_judgment": dedup_judgment(judg),
        "fixed": bool(args.fix and auto),
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
