#!/usr/bin/env python3
"""Append one queue-run section to the committed queue digest.

usage: append_digest.py --results <results.json> [--digest <digest.md>]

Without --digest the target is resolved to the MAIN checkout's
data/queue/digest.md: the skill runs inside a routine worktree whose
files are discarded with the worktree, so writing the worktree's copy
would silently lose the run record. Resolution + guards:

  1. `git rev-parse --path-format=absolute --git-common-dir` — the
     shared .git directory; its parent is the main checkout regardless
     of which worktree we run from. Abort if it does not end in `.git`
     (bare repo / unexpected layout).
  2. The resolved digest must be TRACKED there
     (`git ls-files --error-unmatch`) — abort loudly otherwise; never
     create or blind-write a file we merely guessed at.

With --digest (tests, manual use) resolution is skipped, but the marker
check below still applies.

The digest must contain exactly one section marker:

  <!-- queue-digest:sections -->   new sections inserted directly below
                                   (newest first)

Sections are append-only — this is an audit log, and a same-night manual
run must not erase the routine run's record. Re-applying the SAME
results file (identical run_id) is rejected instead of duplicated.

Results JSON schema (composed by the /queue-consumer session):

{
  "run_id": "2026-06-14 01:30",     // unique per run; section heading
  "notes": "optional free text",
  "issues": [
    {
      "number": 530,
      "title": "Fix README typo",
      "outcome": "completed",       // completed | skipped-pr-open |
                                    // skipped-needs-detail |
                                    // blocked-policy |
                                    // blocked-implementation
      "branch": "agent/issue-530",  // null when never branched
      "pr_url": "https://...",      // null unless completed
      "note": "one-line context"
    }
  ]
}
"""

import argparse
import json
import os
import re
import subprocess
import sys

SECTIONS_MARKER = "<!-- queue-digest:sections -->"
DIGEST_RELPATH = "data/queue/digest.md"
OUTCOMES = (
    "completed", "skipped-pr-open", "skipped-needs-detail",
    "blocked-policy", "blocked-implementation",
)


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def resolve_main_digest():
    """Locate the main checkout's tracked digest; abort loudly on doubt."""
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True).stdout.strip()
    if os.path.basename(common) != ".git":
        sys.exit(f"unexpected --git-common-dir {common!r} (bare repo?) — "
                 "pass --digest explicitly")
    main_root = os.path.dirname(common)
    tracked = subprocess.run(
        ["git", "-C", main_root, "ls-files", "--error-unmatch",
         DIGEST_RELPATH],
        capture_output=True, text=True)
    if tracked.returncode != 0:
        sys.exit(f"{DIGEST_RELPATH} is not tracked in {main_root} — "
                 "refusing to write (wrong target would lose the run "
                 "record). Pass --digest explicitly if this is intended.")
    return os.path.join(main_root, DIGEST_RELPATH)


def render_section(results):
    issues = results.get("issues", [])
    counts = {}
    for issue in issues:
        counts[issue["outcome"]] = counts.get(issue["outcome"], 0) + 1
    summary = " / ".join(f"{k} {v}" for k, v in sorted(counts.items()))
    lines = [
        f"## {results['run_id']}",
        "",
        f"Issues: {len(issues)}" + (f" ({summary})" if summary else ""),
        "",
        "| # | title | outcome | branch | PR | note |",
        "|---|---|---|---|---|---|",
    ]
    for issue in issues:
        lines.append("| " + " | ".join([
            cell(issue.get("number")), cell(issue.get("title")),
            cell(issue.get("outcome")), cell(issue.get("branch")),
            cell(issue.get("pr_url")), cell(issue.get("note")),
        ]) + " |")
    if results.get("notes"):
        lines += ["", f"Notes: {results['notes']}"]
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--digest",
                        help="explicit digest path (skips main-checkout "
                             "resolution; tests / manual use)")
    args = parser.parse_args()

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)
    run_id = results.get("run_id", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", run_id):
        sys.exit(f"results.run_id must be 'YYYY-MM-DD HH:MM', got: {run_id!r}")
    for issue in results.get("issues", []):
        if issue.get("outcome") not in OUTCOMES:
            sys.exit(f"issue {issue.get('number')}: outcome must be one of "
                     f"{OUTCOMES}, got: {issue.get('outcome')!r}")

    digest_path = args.digest or resolve_main_digest()
    with open(digest_path, encoding="utf-8") as f:
        digest = f.read()
    if digest.count(SECTIONS_MARKER) != 1:
        sys.exit(f"digest must contain exactly one '{SECTIONS_MARKER}'")
    if f"## {run_id}" in digest:
        sys.exit(f"section '## {run_id}' already exists — same results "
                 "applied twice? Append-only log, refusing to duplicate.")

    head, marker, tail = digest.partition(SECTIONS_MARKER)
    section = render_section(results)
    with open(digest_path, "w", encoding="utf-8") as f:
        f.write(head + marker + "\n\n" + section + tail.lstrip("\n")
                + ("" if tail.endswith("\n") or not tail.strip() else "\n"))

    print(f"appended section {run_id} "
          f"({len(results.get('issues', []))} issue(s)) to {digest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
