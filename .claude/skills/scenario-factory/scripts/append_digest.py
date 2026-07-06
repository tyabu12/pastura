#!/usr/bin/env python3
"""Append one factory-cycle section to the local digest, date-idempotently.

usage: append_digest.py --results <results.json> --digest <digest.md>

The digest is a LOCAL log (gitignored — not committed). If the target
file is absent (clean clone / first run), it is bootstrapped from a
scaffold; the canonical promotion docs live in the skill's SKILL.md
§ Promotion, with only a one-line `Promotion:` pointer kept in the file.

The digest must contain both marker comments:

  <!-- factory-digest:sections -->    new sections inserted directly below
                                      (newest first)
  <!-- factory-digest:promotion -->   promotion pointer footer; never modified

If a section for the same date already exists between the markers it is
REPLACED (so re-running a partially-failed cycle is safe) and a warning
goes to stderr. Missing markers are a hard error — never blind-append.

Results JSON schema (composed by the /scenario-factory session):

{
  "date": "YYYY-MM-DD",
  "model": "gemma-4-E2B-it-Q4_K_M",
  "notes": "optional free text",
  "scenarios": [
    {
      "id": "factory_20260613_example",
      "name": "...", "theme": "...",
      "axis": "branching / roleplay",   // optional: the under-represented
                                        // gallery axis this scenario targeted
                                        // (SKILL.md Step 1.5); omitted → em-dash
      "yaml": "data/factory/scenarios/2026-06-13/....yaml",
      "run_log": "data/factory/runs/2026-06-13/....jsonl",
      "status": "ok|failed|config_error",
      "attempts": 1, "duration_sec": 123.4,
      "scores": {"coherence": 4, "interaction": 3, "breakdown_free": 5,
                 "humor": 2, "development": 3},   // null when not ok
      "comment": "one-line judge comment",
      "error": null
    }
  ]
}

`development` = cross-round development/surprise, universal across categories; null allowed for single-round scenarios (renders as `–`, same as the existing null-humor handling).
"""

import argparse
import json
import os
import re
import sys

SECTIONS_MARKER = "<!-- factory-digest:sections -->"
PROMOTION_MARKER = "<!-- factory-digest:promotion -->"
RUBRIC_KEYS = ["coherence", "interaction", "breakdown_free", "humor", "development"]
# Bootstrap scaffold for a fresh local log (the digest is gitignored, so a
# clean clone / first run has nothing to append to). Carries BOTH markers
# and a `Promotion:`-prefixed pointer line so the dual-marker validator and
# the SKILL.md § Promotion cross-reference both stay intact.
SCAFFOLD = f"""# Scenario Factory Digest

Local log of `/scenario-factory` cycles, newest first. Gitignored — a
local journal, not committed. Promoting a winning scenario (bundled
preset or shared-scenario gallery) goes through an /orchestrate PR; see
the skill's SKILL.md § Promotion.

{SECTIONS_MARKER}

{PROMOTION_MARKER}
Promotion: channels documented in `.claude/skills/scenario-factory/SKILL.md` § Promotion.
"""


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_section(results):
    scenarios = results.get("scenarios", [])
    counts = {"ok": 0, "failed": 0, "config_error": 0}
    for s in scenarios:
        counts[s.get("status", "failed")] = counts.get(s.get("status", "failed"), 0) + 1

    lines = [
        f"## {results['date']}",
        "",
        f"Model: {results.get('model', '?')} | Scenarios: {len(scenarios)} "
        f"(ok {counts['ok']} / failed {counts['failed']} / "
        f"config_error {counts['config_error']})",
        "",
        "| id | name | theme | axis | status | (a) coherence | (b) interaction "
        "| (c) breakdown-free | (d) humor | (e) development | comment |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for s in scenarios:
        scores = s.get("scores") or {}
        comment = s.get("comment") or ""
        if s.get("status") != "ok" and s.get("error"):
            comment = f"{comment} error: {s['error']}".strip()
        row = [
            cell(s.get("id")), cell(s.get("name")), cell(s.get("theme")),
            cell(s.get("axis")), cell(s.get("status")),
        ]
        row += [cell(scores.get(k)) for k in RUBRIC_KEYS]
        row.append(cell(comment))
        lines.append("| " + " | ".join(row) + " |")
    if results.get("notes"):
        lines += ["", f"Notes: {results['notes']}"]
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--digest", required=True)
    args = parser.parse_args()

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", results.get("date", "")):
        print(f"results.date must be YYYY-MM-DD, got: {results.get('date')!r}",
              file=sys.stderr)
        return 1

    if not os.path.exists(args.digest):
        # Local-log model: the digest is gitignored, so a clean clone or
        # the very first run has no file. Bootstrap the scaffold.
        os.makedirs(os.path.dirname(args.digest) or ".", exist_ok=True)
        with open(args.digest, "w", encoding="utf-8") as f:
            f.write(SCAFFOLD)

    with open(args.digest, encoding="utf-8") as f:
        digest = f.read()
    for marker in (SECTIONS_MARKER, PROMOTION_MARKER):
        if digest.count(marker) != 1:
            print(f"digest must contain exactly one '{marker}'", file=sys.stderr)
            return 1
    if digest.index(SECTIONS_MARKER) > digest.index(PROMOTION_MARKER):
        print("sections marker must precede promotion marker", file=sys.stderr)
        return 1

    head, _, tail = digest.partition(SECTIONS_MARKER)
    body, _, footer = tail.partition(PROMOTION_MARKER)

    # Date idempotency: drop an existing same-date section (everything from
    # its `## <date>` heading up to the next `## ` heading or body end).
    pattern = re.compile(
        rf"^## {re.escape(results['date'])}\n.*?(?=^## |\Z)",
        re.DOTALL | re.MULTILINE)
    body, replaced = pattern.subn("", body)
    if replaced:
        print(f"warning: replaced existing section for {results['date']}",
              file=sys.stderr)

    section = render_section(results)
    body = "\n\n" + section + "\n" + body.strip("\n") + ("\n\n" if body.strip("\n") else "\n")

    with open(args.digest, "w", encoding="utf-8") as f:
        f.write(head + SECTIONS_MARKER + body + PROMOTION_MARKER + footer)

    action = "replaced" if replaced else "appended"
    print(f"{action} section {results['date']} "
          f"({len(results.get('scenarios', []))} scenario(s)) in {args.digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
