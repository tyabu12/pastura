#!/usr/bin/env python3
"""Append one /model-eval scorecard section to the local eval digest.

This is the THIRD fork of `.claude/skills/scenario-factory/scripts/
append_digest.py`'s marker / same-key-idempotency / bootstrap core —
`append_digest.py` (factory) -> `.claude/skills/scenario-refine/scripts/
append_audit.py` (refine) -> this file. If the shared 2-marker core ever
needs a real fix (bootstrap, marker validation, section-replace mechanics),
sweep all three files.

usage: append_eval.py --results <results.json> --journal <eval-digest.md>

The journal is a LOCAL log (gitignored — not committed). If absent it is
bootstrapped from a scaffold.

Section key is (date, model.profile_id) — unlike the factory/refine digests
(date-only), a single day can run the battery against more than one model
profile, so each gets its own section; re-appending the SAME (date,
profile_id) REPLACES that section (idempotent re-run of a partially-failed
battery), leaving other profiles' sections for that date untouched.

Each section embeds a machine-readable `<!-- eval-data: {...} -->` comment
(compact JSON) — the source of truth for a future cycle to parse prior
scorecards for cross-model / cross-date comparison without parsing the
markdown table.

Results JSON schema (composed by the /model-eval session):

{
  "date": "YYYY-MM-DD",
  "model": {"profile_id": "qwen-3-4b-q4-k-m", "gguf": "Qwen3-4B-Q4_K_M"},
  "battery": [
    {
      "scenario_id": "bokete", "language": "ja",
      "status": "ok|failed|config_error",
      "attempts": 1, "language_mismatches": 0, "tok_per_sec": 12.3,
      "rubric": {"coherence": 4, "interaction": 3, "breakdown_free": 5,
                 "development": 3, "payoff": 4, "payoff_axis": "humor"}
                 | null,   // null for failed/config_error cells — no scores
      "comment": "one-line note"
    }
  ],
  "differentiation": "free text: how this model's outputs differ from others",
  "verdict": {"gate": "pass|borderline|fail", "notes": "..."}
}
"""

import argparse
import json
import os
import re
import sys

SECTIONS_MARKER = "<!-- model-eval:sections -->"
# Semantic analogue of append_audit.py's PROMOTION_MARKER footer: a fixed
# pointer to where the actual go/no-go call is made (this journal is a raw
# scorecard log, not itself the decision record).
FOOTER_MARKER = "<!-- model-eval:footer -->"

# Universal axes (coherence/interaction/breakdown_free/development) before
# the category-specific `payoff` — same column order as append_audit.py's
# SCORE_KEYS, for a reader moving between the two journals.
RUBRIC_KEYS = ["coherence", "interaction", "breakdown_free", "development", "payoff"]

SCAFFOLD = f"""# Model Eval Digest

Local log of `/model-eval` battery runs, newest first. Gitignored — a local
scorecard, not committed. Each section embeds a machine-readable `eval-data`
comment (source of truth for cross-model / cross-date comparison without
parsing markdown).

{SECTIONS_MARKER}

{FOOTER_MARKER}
See `.claude/skills/model-eval/SKILL.md` for the battery definition, rubric,
and gate criteria. The `**Gate**:` line in each section is the per-run call;
this file does not aggregate a final recommendation across models.
"""


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def rubric_total(rubric):
    """Sum of the 5 rubric axes, or None when the cell has no rubric (failed
    / config_error rows). `.get(k) or 0` (not `.get(k, 0)`) mirrors
    append_audit.py's total() — `development` may be present-but-null for a
    single-round scenario, and sum() over None raises."""
    if not rubric:
        return None
    return sum(rubric.get(k) or 0 for k in RUBRIC_KEYS)


def validate_results(results):
    """Minimal schema check. Returns an error string, or None if valid."""
    date = results.get("date")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date or ""):
        return f"results.date must be YYYY-MM-DD, got: {date!r}"

    model = results.get("model")
    if not isinstance(model, dict) or not model.get("profile_id"):
        return "results.model must be an object with a non-empty 'profile_id'"

    battery = results.get("battery")
    if not isinstance(battery, list) or not battery:
        return "results.battery must be a non-empty list"
    for i, entry in enumerate(battery):
        if not isinstance(entry, dict):
            return f"results.battery[{i}] must be an object"
        for key in ("scenario_id", "language", "status"):
            if not entry.get(key):
                return f"results.battery[{i}] missing required field {key!r}"

    verdict = results.get("verdict")
    if not isinstance(verdict, dict) or verdict.get("gate") not in (
        "pass", "borderline", "fail",
    ):
        return "results.verdict.gate must be one of pass|borderline|fail"

    return None


def eval_data_comment(results):
    """Build the machine-readable per-section data comment. Includes the
    full battery (status + rubric, `comment` excluded — bulk of size, and
    not needed for programmatic cross-comparison) plus differentiation and
    verdict, so a future cycle can compare models without parsing the
    markdown table."""
    model = results["model"]
    battery = []
    for entry in results.get("battery", []):
        rec = {
            "scenario_id": entry.get("scenario_id"),
            "language": entry.get("language"),
            "status": entry.get("status"),
            "attempts": entry.get("attempts"),
            "language_mismatches": entry.get("language_mismatches"),
            "tok_per_sec": entry.get("tok_per_sec"),
            "rubric": entry.get("rubric"),
        }
        battery.append(rec)
    payload = {
        "date": results["date"],
        "model": {"profile_id": model.get("profile_id"), "gguf": model.get("gguf")},
        "battery": battery,
        "differentiation": results.get("differentiation"),
        "verdict": results.get("verdict"),
    }
    return "<!-- eval-data: " + json.dumps(
        payload, ensure_ascii=False, sort_keys=True
    ) + " -->"


def render_section(results):
    model = results["model"]
    profile_id = model.get("profile_id", "?")
    gguf = model.get("gguf", "?")
    battery = results.get("battery", [])

    counts = {"ok": 0, "failed": 0, "config_error": 0}
    for entry in battery:
        st = entry.get("status", "failed")
        counts[st] = counts.get(st, 0) + 1

    lines = [
        f"## {results['date']} — {profile_id} ({gguf})",
        "",
        f"Battery: {len(battery)} "
        f"(ok {counts['ok']} / failed {counts['failed']} / "
        f"config_error {counts['config_error']})",
        "",
        eval_data_comment(results),
        "",
        "| scenario | lang | status | attempts | lang-mismatch | tok/s "
        "| (a) coherence | (b) interaction | (c) breakdown_free "
        "| (d) development | (e) payoff | total | comment |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for entry in battery:
        rubric = entry.get("rubric") or {}
        total = rubric_total(entry.get("rubric"))
        payoff = rubric.get("payoff")
        payoff_cell = (
            f"{rubric.get('payoff_axis', 'payoff')} {payoff}"
            if payoff is not None
            else None
        )
        row = [
            cell(entry.get("scenario_id")), cell(entry.get("language")),
            cell(entry.get("status")), cell(entry.get("attempts")),
            cell(entry.get("language_mismatches")), cell(entry.get("tok_per_sec")),
            cell(rubric.get("coherence")), cell(rubric.get("interaction")),
            cell(rubric.get("breakdown_free")), cell(rubric.get("development")),
            cell(payoff_cell), cell(total), cell(entry.get("comment")),
        ]
        lines.append("| " + " | ".join(row) + " |")

    lines.append("")
    if results.get("differentiation"):
        lines += [f"Differentiation: {results['differentiation']}", ""]
    verdict = results.get("verdict") or {}
    lines.append(f"**Gate**: {verdict.get('gate', '?')}")
    if verdict.get("notes"):
        lines.append(f"Notes: {verdict['notes']}")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True)
    parser.add_argument("--journal", required=True)
    args = parser.parse_args()

    with open(args.results, encoding="utf-8") as f:
        results = json.load(f)

    err = validate_results(results)
    if err:
        print(f"append_eval: {err}", file=sys.stderr)
        return 1

    if not os.path.exists(args.journal):
        os.makedirs(os.path.dirname(args.journal) or ".", exist_ok=True)
        with open(args.journal, "w", encoding="utf-8") as f:
            f.write(SCAFFOLD)

    with open(args.journal, encoding="utf-8") as f:
        journal = f.read()
    for marker in (SECTIONS_MARKER, FOOTER_MARKER):
        if journal.count(marker) != 1:
            print(f"journal must contain exactly one '{marker}'", file=sys.stderr)
            return 1
    if journal.index(SECTIONS_MARKER) > journal.index(FOOTER_MARKER):
        print("sections marker must precede footer marker", file=sys.stderr)
        return 1

    head, _, tail = journal.partition(SECTIONS_MARKER)
    body, _, footer = tail.partition(FOOTER_MARKER)

    date = results["date"]
    profile_id = results["model"]["profile_id"]
    section = render_section(results)

    # Section key = (date, profile_id): the heading is
    # "## <date> — <profile_id> (<gguf>)"; gguf is matched loosely (`.*?`)
    # so a re-run that changes the recorded gguf stem still replaces the
    # prior section for the same date+profile rather than duplicating it.
    pattern = re.compile(
        rf"^## {re.escape(date)} — {re.escape(profile_id)} \(.*?\)\n"
        r".*?(?=^## |\Z)",
        re.DOTALL | re.MULTILINE,
    )
    body, replaced = pattern.subn("", body)
    if replaced:
        print(
            f"warning: replaced existing section for {date} — {profile_id}",
            file=sys.stderr,
        )

    stripped = body.strip("\n")
    body = "\n\n" + section + "\n" + stripped + ("\n\n" if stripped else "\n")

    with open(args.journal, "w", encoding="utf-8") as f:
        f.write(head + SECTIONS_MARKER + body + FOOTER_MARKER + footer)

    action = "replaced" if replaced else "appended"
    print(
        f"{action} section {date} — {profile_id} "
        f"({len(results.get('battery', []))} scenario(s)) in {args.journal}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
