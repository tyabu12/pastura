#!/usr/bin/env python3
"""Append one /scenario-refine audit section to the local journal.

This is a FORK of `.claude/skills/scenario-factory/scripts/append_digest.py`:
it reuses that script's 2-marker / date-idempotency / bootstrap structure but
in its own `audit-digest:` marker namespace, and ADDS two things the factory
digest does not need:

  1. A machine-readable `<!-- audit-data: {...} -->` comment per section — the
     robust source of truth for both this script's baseline delta and
     select_inventory.py's rotation (parsing the human table would break on
     escaped pipes in comments).
  2. A baseline DELTA per scenario: the score change vs the most recent PRIOR
     ok evaluation of the same id+model (regression detection), or — for an
     A/B improvement candidate — vs its baseline in the SAME run.

The fork is deliberate (different marker namespace, extra columns); the two
scripts are expected to drift only in those respects. If the shared 2-marker
core ever needs a real fix, fix both.

usage: append_audit.py --results <results.json> --journal <audit-digest.md>

The journal is a LOCAL log (gitignored — not committed). If absent it is
bootstrapped from a scaffold. Promotion of a winning scenario (preset or
gallery) is a SEPARATE human-driven /orchestrate PR — never automated here;
see SKILL.md § Promotion.

Results JSON schema (composed by the /scenario-refine session):

{
  "date": "YYYY-MM-DD",
  "model": "gemma-4-E2B-it-Q4_K_M",
  "notes": "optional free text",
  "scenarios": [
    {
      "id": "bokete",
      "name": "...", "channel": "preset|gallery", "category": "creative",
      "yaml": "Pastura/Pastura/Resources/Presets/bokete.yaml",
      "run_log": "data/factory/audit-runs/2026-06-21/bokete.jsonl",
      "status": "ok|failed|config_error",
      "attempts": 1, "duration_sec": 123.4,
      "scores": {"coherence": 4, "interaction": 3,
                 "breakdown_free": 5, "payoff": 2},   // null when not ok
      "payoff_axis": "humor",
      "comment": "one-line judge comment",
      "error": null,
      "candidate_of": null    // set to a baseline id for an A/B v2 candidate
    }
  ]
}
"""

import argparse
import json
import os
import re
import sys

SECTIONS_MARKER = "<!-- audit-digest:sections -->"
PROMOTION_MARKER = "<!-- audit-digest:promotion -->"
COMMON_AXES = ["coherence", "interaction", "breakdown_free"]
SCORE_KEYS = COMMON_AXES + ["payoff"]
# Δtotal at or below this flags a regression (⚠️). A drop of 2 across the
# 4-axis total is the smallest change unlikely to be sampling noise.
REGRESSION_THRESHOLD = -2

# Must stay byte-identical to select_inventory.py's copy — the writer and
# reader of the same audit-data contract. Change both or neither.
AUDIT_DATA_RE = re.compile(r"<!--\s*audit-data:\s*(\{.*?\})\s*-->")

SCAFFOLD = f"""# Scenario Refine Audit Digest

Local log of `/scenario-refine` cycles, newest first. Gitignored — a local
journal, not committed. Each section embeds a machine-readable `audit-data`
comment (the source of truth for rotation + baseline delta). Promoting a
polished scenario (bundled preset or shared-scenario gallery) is a SEPARATE
human-driven /orchestrate PR; see the skill's SKILL.md § Promotion.

{SECTIONS_MARKER}

{PROMOTION_MARKER}
Promotion: channels documented in `.claude/skills/scenario-refine/SKILL.md` § Promotion.
"""


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def total(scores):
    if not scores:
        return None
    return sum(scores.get(k, 0) for k in SCORE_KEYS)


def prior_ok_scores(journal_text, model, exclude_date):
    """Most-recent prior ok scores per id (same model), excluding exclude_date.

    Reads the machine-readable audit-data comments, not the human tables.
    Returns {id: scores_dict}. A re-run on the same date excludes that date
    so the section being replaced never becomes its own baseline.

    An ok record missing any of the 4 score axes is skipped as a baseline AND
    a `warning:` is emitted — an ok run should always carry a full score set,
    so an incomplete one signals a malformed compose rather than being
    silently treated as "no prior baseline".
    """
    best = {}  # id -> (date, scores)
    for blob in AUDIT_DATA_RE.findall(journal_text):
        try:
            data = json.loads(blob)
        except json.JSONDecodeError:
            continue
        if data.get("model") != model:
            continue
        date = data.get("date", "")
        if date == exclude_date:
            continue
        for sid, rec in (data.get("scenarios") or {}).items():
            if rec.get("status") != "ok":
                continue
            scores = {k: rec.get(k) for k in SCORE_KEYS if rec.get(k) is not None}
            if len(scores) < len(SCORE_KEYS):
                print(f"warning: ok record {sid!r} on {date} is missing score "
                      f"axes {sorted(set(SCORE_KEYS) - set(scores))} — skipped "
                      "as a baseline (malformed compose?)", file=sys.stderr)
                continue
            if sid not in best or date > best[sid][0]:
                best[sid] = (date, scores)
    return {sid: s for sid, (_, s) in best.items()}


def audit_data_comment(results):
    """Build the machine-readable per-section data comment.

    Includes EVERY evaluated id (so rotation counts a failed run as
    "evaluated" and does not retry it every night), but scores only for ok
    runs (so failed runs never feed the baseline delta).
    """
    scenarios = {}
    for s in results.get("scenarios", []):
        sid = s.get("id")
        rec = {"status": s.get("status", "failed")}
        if s.get("status") == "ok" and s.get("scores"):
            for k in SCORE_KEYS:
                rec[k] = s["scores"].get(k)
            rec["payoff_axis"] = s.get("payoff_axis")
        if s.get("candidate_of"):
            rec["candidate_of"] = s["candidate_of"]
        scenarios[sid] = rec
    payload = {"date": results["date"], "model": results.get("model", "?"),
               "scenarios": scenarios}
    return "<!-- audit-data: " + json.dumps(payload, ensure_ascii=False,
                                            sort_keys=True) + " -->"


def delta_cell(scenario, this_run_ok, prior):
    """Δ column: A/B vs same-run baseline for candidates, else regression."""
    if scenario.get("status") != "ok" or not scenario.get("scores"):
        return "–"
    cur = total(scenario["scores"])
    base_of = scenario.get("candidate_of")
    if base_of:
        base = this_run_ok.get(base_of)
        if base is None:
            return "vs base: ?"
        d = cur - total(base)
        return f"vs base {d:+d}{' ✅' if d > 0 else ''}"
    base = prior.get(scenario["id"])
    if base is None:
        return "–"  # no prior baseline yet
    d = cur - total(base)
    return f"{d:+d}{' ⚠️' if d <= REGRESSION_THRESHOLD else ''}"


def render_section(results, journal_text):
    scenarios = results.get("scenarios", [])
    counts = {"ok": 0, "failed": 0, "config_error": 0}
    for s in scenarios:
        st = s.get("status", "failed")
        counts[st] = counts.get(st, 0) + 1

    prior = prior_ok_scores(journal_text, results.get("model", "?"),
                            results["date"])
    this_run_ok = {s["id"]: s["scores"] for s in scenarios
                   if s.get("status") == "ok" and s.get("scores")}

    lines = [
        f"## {results['date']}",
        "",
        f"Model: {results.get('model', '?')} | Scenarios: {len(scenarios)} "
        f"(ok {counts['ok']} / failed {counts['failed']} / "
        f"config_error {counts['config_error']})",
        "",
        audit_data_comment(results),
        "",
        "| id | name | channel | category | status | (a) | (b) | (c) "
        "| (d) payoff | Δ | comment |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for s in scenarios:
        scores = s.get("scores") or {}
        comment = s.get("comment") or ""
        if s.get("status") != "ok" and s.get("error"):
            comment = f"{comment} error: {s['error']}".strip()
        payoff = scores.get("payoff")
        payoff_cell = (f"{s.get('payoff_axis', 'payoff')} {payoff}"
                       if payoff is not None else None)
        row = [
            cell(s.get("id")), cell(s.get("name")), cell(s.get("channel")),
            cell(s.get("category")), cell(s.get("status")),
            cell(scores.get("coherence")), cell(scores.get("interaction")),
            cell(scores.get("breakdown_free")), cell(payoff_cell),
            cell(delta_cell(s, this_run_ok, prior)), cell(comment),
        ]
        lines.append("| " + " | ".join(row) + " |")
    if results.get("notes"):
        lines += ["", f"Notes: {results['notes']}"]
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--journal", required=True)
    args = parser.parse_args()

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", results.get("date", "")):
        print(f"results.date must be YYYY-MM-DD, got: {results.get('date')!r}",
              file=sys.stderr)
        return 1

    if not os.path.exists(args.journal):
        os.makedirs(os.path.dirname(args.journal) or ".", exist_ok=True)
        with open(args.journal, "w", encoding="utf-8") as f:
            f.write(SCAFFOLD)

    with open(args.journal, encoding="utf-8") as f:
        journal = f.read()
    for marker in (SECTIONS_MARKER, PROMOTION_MARKER):
        if journal.count(marker) != 1:
            print(f"journal must contain exactly one '{marker}'", file=sys.stderr)
            return 1
    if journal.index(SECTIONS_MARKER) > journal.index(PROMOTION_MARKER):
        print("sections marker must precede promotion marker", file=sys.stderr)
        return 1

    head, _, tail = journal.partition(SECTIONS_MARKER)
    body, _, footer = tail.partition(PROMOTION_MARKER)

    # Baseline delta reads PRIOR sections, so compute the section against the
    # body with any same-date section still present (prior_ok_scores excludes
    # the current date itself), THEN drop the old same-date section.
    section = render_section(results, body)

    pattern = re.compile(
        rf"^## {re.escape(results['date'])}\n.*?(?=^## |\Z)",
        re.DOTALL | re.MULTILINE)
    body, replaced = pattern.subn("", body)
    if replaced:
        print(f"warning: replaced existing section for {results['date']}",
              file=sys.stderr)

    stripped = body.strip("\n")
    body = "\n\n" + section + "\n" + stripped + ("\n\n" if stripped else "\n")

    with open(args.journal, "w", encoding="utf-8") as f:
        f.write(head + SECTIONS_MARKER + body + PROMOTION_MARKER + footer)

    action = "replaced" if replaced else "appended"
    print(f"{action} section {results['date']} "
          f"({len(results.get('scenarios', []))} scenario(s)) in {args.journal}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
