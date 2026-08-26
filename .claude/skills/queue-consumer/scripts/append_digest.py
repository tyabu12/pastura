#!/usr/bin/env python3
"""Append one queue-run section to the local queue digest.

usage: append_digest.py --results <results.json> [--digest <digest.md>]

The digest is a LOCAL log (gitignored — not committed). Without --digest
the target is resolved to the MAIN checkout's data/queue/digest.md: the
skill runs inside a routine worktree whose files are discarded with the
worktree, so writing the worktree's copy would lose the run record.
Resolution:

  1. `git rev-parse --path-format=absolute --git-common-dir` — the
     shared .git directory; its parent is the main checkout regardless
     of which worktree we run from. Abort if it does not end in `.git`
     (bare repo / unexpected layout) — this is the real wrong-target
     catch now that the tracked-check is gone.
  2. If the digest is absent there, bootstrap a fresh scaffold (the log
     is no longer tracked, so a clean clone / first run has no file) —
     under the lock, since creating the target is part of the
     read-modify-write. A present file must still carry the section
     marker — a stray wrong target would lack it.

With --digest (tests, manual use) resolution is skipped, but the marker
check below still applies.

This is the FOURTH fork of `.claude/skills/scenario-factory/scripts/
append_digest.py`'s marker / bootstrap / flock core (the others: refine's
append_audit.py, model-eval's append_eval.py); all four now carry the flock
(#1542 swept it across the set). If that shared core ever needs a real fix,
sweep all four files.

The digest read-modify-write — resolution's bootstrap-if-absent included —
runs under an exclusive flock on `<digest>.lock`. This fork is the most
exposed member of the family: it deliberately targets the MAIN checkout, so
runs from every routine worktree write ONE shared file, and it is
append-only, so an interleaved read-modify-write drops a whole run record
with no key to recover it from.

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
import contextlib
import fcntl
import json
import os
import re
import subprocess
import sys

SECTIONS_MARKER = "<!-- queue-digest:sections -->"
DIGEST_RELPATH = "data/queue/digest.md"
# Bootstrap scaffold for a fresh local log (the digest is gitignored, so a
# clean clone / first run has nothing to append to). One section marker.
SCAFFOLD = f"""# Overnight Issue Queue — digest

Local log of `/queue-consumer` runs, newest first. Gitignored — a local
journal, not committed; see the skill's SKILL.md.

{SECTIONS_MARKER}
"""
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
    """Locate the main checkout's local digest. Resolution only — the
    bootstrap-if-absent moved into _append_locked(): creating the target is
    itself part of the read-modify-write and must happen under the lock, or
    two first runs racing from different worktrees each write a scaffold and
    one loses its section."""
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True).stdout.strip()
    if os.path.basename(common) != ".git":
        sys.exit(f"unexpected --git-common-dir {common!r} (bare repo?) — "
                 "pass --digest explicitly")
    main_root = os.path.dirname(common)
    return os.path.join(main_root, DIGEST_RELPATH)


@contextlib.contextmanager
def digest_lock(digest_path):
    """Exclusive flock on `<digest>.lock` around the whole read-modify-write.

    Every routine worktree resolves to the SAME main-checkout digest, so two
    runs would otherwise both read the body, both write, and the loser's
    section would vanish — and this log is append-only, so there is no key to
    recover it from. The lock file is separate from the digest so the
    truncating write below can never drop it. Mirrors the factory digest's
    digest_lock() / the refine journal's journal_lock()."""
    lock_path = digest_path + ".lock"
    os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


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

    # Resolve first, lock the resolved path, then bootstrap / read / write
    # under it. Parsing and validation above touch no target file, so they
    # stay outside the lock.
    may_bootstrap = args.digest is None
    digest_path = args.digest or resolve_main_digest()
    with digest_lock(digest_path):
        return _append_locked(digest_path, results, run_id, may_bootstrap)


def _append_locked(digest_path, results, run_id, may_bootstrap):
    """Bootstrap-if-absent, read, and rewrite the digest. Caller must hold
    digest_lock()."""
    if may_bootstrap and not os.path.exists(digest_path):
        # Local-log model: the digest is gitignored, so a clean clone or the
        # very first run has no file. Bootstrap the scaffold (with the section
        # marker) rather than aborting. Re-checked here, under the lock — the
        # racing sibling may have created it since resolution.
        os.makedirs(os.path.dirname(digest_path), exist_ok=True)
        with open(digest_path, "w", encoding="utf-8") as f:
            f.write(SCAFFOLD)

    with open(digest_path, encoding="utf-8") as f:
        digest = f.read()
    if digest.count(SECTIONS_MARKER) != 1:
        sys.exit(f"digest must contain exactly one '{SECTIONS_MARKER}'")
    if f"## {run_id}" in digest:
        sys.exit(f"section '## {run_id}' already exists — same results "
                 "applied twice? Append-only log, refusing to duplicate.")

    head, marker, tail = digest.partition(SECTIONS_MARKER)
    section = render_section(results)  # ends with exactly one "\n"
    # A blank line must separate the new section from a pre-existing one,
    # or the old "## <run_id>" heading glues onto the new section's last
    # paragraph and stops rendering as a heading.
    tail_body = tail.lstrip("\n")
    out = head + marker + "\n\n" + section
    if tail_body:
        out += "\n" + tail_body
    with open(digest_path, "w", encoding="utf-8") as f:
        f.write(out)

    print(f"appended section {run_id} "
          f"({len(results.get('issues', []))} issue(s)) to {digest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
