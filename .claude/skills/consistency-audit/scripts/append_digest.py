#!/usr/bin/env python3
"""Append one consistency-audit run section to the committed audit digest.

usage: append_digest.py --results <results.json> [--digest <digest.md>]

Invocation model: a MANUAL run executes from the main checkout, so the
digest path resolves to that same checkout. A future SCHEDULED run will
execute inside a routine-provided worktree (mirroring queue-consumer);
its files are discarded with the worktree, so the digest must be written
to the MAIN checkout to persist. `resolve_main_digest()` handles both:
`git rev-parse --git-common-dir` resolves to the shared `.git`, whose
parent is the main checkout regardless of which worktree we run from.
(From the main checkout it simply resolves to that checkout — a no-op,
but retained so the same helper works once scheduling moves to worktrees.)

Guards (refuse to write a file we merely guessed at):
  1. `--git-common-dir` must end in `.git` (else: bare/unexpected layout).
  2. The resolved digest must be TRACKED there (`git ls-files
     --error-unmatch`) — abort loudly otherwise.

With --digest (tests, manual override) resolution is skipped, but the
marker + duplicate-run_id guards below still apply.

The digest must contain exactly one section marker:

  <!-- audit-digest:sections -->   new sections inserted directly below
                                   (newest first)

Sections are append-only (an audit log). Re-applying the SAME results
file (identical run_id) is rejected, not duplicated.

Results JSON schema (composed by the /consistency-audit session):

{
  "run_id": "2026-06-14 02:00",        // unique per run; section heading
  "auto_fixable": 1,                    // dry-run count
  "needs_judgment": 0,                  // dry-run count
  "auto_fix_status": "opened",          // opened | skipped-open-audit-pr | none
  "auto_fix_pr": "https://...",         // opened: the new PR;
                                        // skipped-open-audit-pr: the blocking PR;
                                        // none: null
  "issues": ["https://..."],            // issue urls filed this run (or [])
  "notes": "optional free text"
}
"""

import argparse
import json
import os
import re
import subprocess
import sys

SECTIONS_MARKER = "<!-- audit-digest:sections -->"
DIGEST_RELPATH = "data/audit/digest.md"
AUTO_FIX_STATUSES = ("opened", "skipped-open-audit-pr", "none")


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
        sys.exit(f"{DIGEST_RELPATH} is not tracked in {main_root} — refusing "
                 "to write (wrong target would lose the run record). Pass "
                 "--digest explicitly if this is intended.")
    return os.path.join(main_root, DIGEST_RELPATH)


def _clean(text):
    """One-line, pipe-safe rendering of free text."""
    return str(text).replace("\n", " ").strip()


def auto_fix_line(results):
    status = results["auto_fix_status"]
    pr = results.get("auto_fix_pr")
    if status == "opened":
        return f"- Auto-fix PR: {pr}"
    if status == "skipped-open-audit-pr":
        return (f"- Auto-fix PR: skipped — open audit PR {pr} still pending "
                "(auto-fix paused until it is merged or closed)")
    return "- Auto-fix PR: none (no auto-fixable drift)"


def render_section(results):
    issues = results.get("issues", [])
    lines = [
        f"## {results['run_id']}",
        "",
        f"Dry-run: auto_fixable {results['auto_fixable']}, "
        f"needs_judgment {results['needs_judgment']}",
        "",
        auto_fix_line(results),
        "- Issues filed: " + (", ".join(issues) if issues else "none"),
    ]
    if results.get("notes"):
        lines += ["", f"Notes: {_clean(results['notes'])}"]
    lines.append("")
    return "\n".join(lines)


def validate(results):
    run_id = results.get("run_id", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", run_id):
        sys.exit(f"results.run_id must be 'YYYY-MM-DD HH:MM', got: {run_id!r}")
    for key in ("auto_fixable", "needs_judgment"):
        if not isinstance(results.get(key), int):
            sys.exit(f"results.{key} must be an integer")
    status = results.get("auto_fix_status")
    if status not in AUTO_FIX_STATUSES:
        sys.exit(f"results.auto_fix_status must be one of {AUTO_FIX_STATUSES}, "
                 f"got: {status!r}")
    # A status that implies a PR must carry its url, or the section renders a
    # bare "None" — assert it rather than emit a broken record.
    if status in ("opened", "skipped-open-audit-pr") and not results.get(
            "auto_fix_pr"):
        sys.exit(f"results.auto_fix_pr is required when auto_fix_status is "
                 f"{status!r}")
    issues = results.get("issues", [])
    if not isinstance(issues, list) or not all(
            isinstance(x, str) for x in issues):
        sys.exit("results.issues must be a list of strings")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--digest",
                        help="explicit digest path (skips main-checkout "
                             "resolution; tests / manual use)")
    args = parser.parse_args()

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)
    validate(results)
    run_id = results["run_id"]

    digest_path = args.digest or resolve_main_digest()
    with open(digest_path, encoding="utf-8") as f:
        digest = f.read()
    if digest.count(SECTIONS_MARKER) != 1:
        sys.exit(f"digest must contain exactly one '{SECTIONS_MARKER}'")
    if f"## {run_id}" in digest:
        sys.exit(f"section '## {run_id}' already exists — same results "
                 "applied twice? Append-only log, refusing to duplicate.")

    head, marker, tail = digest.partition(SECTIONS_MARKER)
    section = render_section(results)  # ends with exactly one "\n"
    # A blank line separates the new section from a pre-existing one, or the
    # old "## <run_id>" heading glues onto the new section and stops rendering.
    tail_body = tail.lstrip("\n")
    out = head + marker + "\n\n" + section
    if tail_body:
        out += "\n" + tail_body
    with open(digest_path, "w", encoding="utf-8") as f:
        f.write(out)

    print(f"appended section {run_id} to {digest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
