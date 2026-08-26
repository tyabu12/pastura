#!/usr/bin/env python3
"""Append one /scenario-refine audit section to the local journal.

This is a FORK of `.claude/skills/scenario-factory/scripts/append_digest.py`:
it reuses that script's 2-marker / (date, run_id)-idempotency / flock /
bootstrap structure but in its own `audit-digest:` marker namespace, and ADDS
two things the factory digest does not need:

  1. A machine-readable `<!-- audit-data: {...} -->` comment per section — the
     robust source of truth for both this script's baseline delta and
     select_inventory.py's rotation (parsing the human table would break on
     escaped pipes in comments).
  2. A baseline DELTA per scenario: the score change vs the most recent PRIOR
     ok evaluation of the same id+model (regression detection), or — for an
     A/B improvement candidate — vs its baseline in the SAME run.

The fork is deliberate (different marker namespace, extra columns); the two
scripts are expected to drift only in those respects. The family is FOUR
scripts, all now carrying the flock (#1542): factory's append_digest.py, this
file, model-eval's append_eval.py, and queue-consumer's append_digest.py. If
the shared core ever needs a real fix, sweep all four.

usage: append_audit.py --results <results.json> --journal <audit-digest.md>
         (results.json must carry `run_id` — the section key is (date, run_id))

If a section for the same (date, run_id) already exists between the markers it
is REPLACED (so re-running a partially-failed cycle is safe) and a warning goes
to stderr. Two cycles sharing a date but not a run_id keep SEPARATE sections —
before #1542 the key was the date alone and the second run of a day silently
wiped the first run's audit record. A legacy date-only `## <date>` heading
never matches the replace pattern, so pre-#1542 sections in an existing local
journal survive untouched.

The journal read-modify-write runs under an exclusive flock on
`<journal>.lock`: sibling runs sharing a main checkout would otherwise
interleave and lose a whole section regardless of key.

The journal is a LOCAL log (gitignored — not committed). If absent it is
bootstrapped from a scaffold. Promotion of a winning scenario (preset or
gallery) is a SEPARATE human-driven /orchestrate PR — never automated here;
see SKILL.md § Promotion.

Results JSON schema (composed by the /scenario-refine session):

{
  "date": "YYYY-MM-DD",
  "run_id": "01:23:45",   // REQUIRED. Recommended value: the cycle's HH:MM:SS
                          // start time — the heading already carries the date,
                          // so only the clock part is needed to disambiguate.
                          // Never auto-derived from the clock: a generated
                          // default would give a re-run of a partially-failed
                          // cycle a NEW key and duplicate its section instead
                          // of replacing it.
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
                 "breakdown_free": 5, "development": 3,
                 "payoff": 2},   // null (the whole dict) when not ok
      // Column order (d) development / (e) payoff: `development` is a UNIVERSAL
      // axis (cross-round development / surprise), so it precedes the
      // category-specific `payoff`. `development` may itself be null for a
      // single-round scenario — total() treats null as 0 and the cell renders –.
      "payoff_axis": "humor",
      "comment": "one-line judge comment",
      "error": null,
      "candidate_of": null    // set to a baseline id for an A/B v2 candidate
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
import sys
from datetime import datetime

SECTIONS_MARKER = "<!-- audit-digest:sections -->"
# run_id shape: short, filesystem/markdown-safe, and heading-legible. The
# clock-shaped subset is additionally range-checked (see validate_run_id).
# Kept identical to append_digest.py's copy — same operator-facing contract.
RUN_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9:_-]{0,15}")
CLOCK_RE = re.compile(r"\d{2}:\d{2}(:\d{2})?")
PROMOTION_MARKER = "<!-- audit-digest:promotion -->"
COMMON_AXES = ["coherence", "interaction", "breakdown_free"]
# `development` is a UNIVERSAL axis (cross-round development / surprise), so it
# slots BEFORE the category-specific `payoff`: columns are (a) coherence /
# (b) interaction / (c) breakdown_free / (d) development / (e) payoff, max 25.
# This deliberately DIFFERS from factory's append_digest.py, where development
# is (e) after humor — scores are keyed by NAME, not letter, so the two orders
# never collide.
SCORE_KEYS = COMMON_AXES + ["development", "payoff"]
# Δtotal at or below this flags a regression (⚠️). A drop of 2 across the
# 5-axis total is the smallest change unlikely to be sampling noise.
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


def validate_run_id(run_id):
    """Return an error string, or None when `run_id` is usable as a section key.

    A clock-shaped value is range-checked so a typo like `99:99` is rejected at
    append time rather than becoming a permanent, unreachable section key."""
    if not isinstance(run_id, str) or not RUN_ID_RE.fullmatch(run_id):
        return (f"results.run_id must match {RUN_ID_RE.pattern} "
                f"(recommended: the cycle's HH:MM:SS start time), "
                f"got: {run_id!r}")
    if CLOCK_RE.fullmatch(run_id):
        fmt = "%H:%M:%S" if run_id.count(":") == 2 else "%H:%M"
        try:
            datetime.strptime(run_id, fmt)
        except ValueError:
            return f"results.run_id looks like a clock time but is not one: {run_id!r}"
    return None


@contextlib.contextmanager
def journal_lock(journal_path):
    """Exclusive flock on `<journal>.lock` around the whole read-modify-write.

    The (date, run_id) key stops two same-day runs from OVERWRITING each other's
    section, but not from interleaving: both read the same body, both write, and
    the loser's section vanishes. The lock file is separate from the journal so
    the truncating write below can never drop it. Mirrors append_digest.py's
    digest_lock()."""
    lock_path = journal_path + ".lock"
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


def cell(value):
    """Escape a markdown table cell; em-dash for absent values."""
    if value is None or value == "":
        return "–"
    return str(value).replace("|", "\\|").replace("\n", " ")


def total(scores):
    if not scores:
        return None
    # `scores.get(k) or 0`, not `.get(k, 0)`: `development` may be present with
    # a null (None) value for single-round scenarios, and sum() over a None
    # raises TypeError. The nightly append must never crash.
    return sum(scores.get(k) or 0 for k in SCORE_KEYS)


def prior_ok_scores(journal_text, model, exclude_date, exclude_run_id):
    """Most-recent prior ok scores per id (same model), excluding one section.

    Reads the machine-readable audit-data comments, not the human tables.
    Returns {id: scores_dict}. The exclusion unit is the (date, run_id) SECTION
    KEY, not the date: only the section this append is about to replace is
    skipped, so it never becomes its own baseline. A sibling run earlier the
    same date is a legitimate prior evaluation and stays one — excluding the
    whole date (the pre-#1542 behaviour) would blank the Δ column for every
    second run of a day.

    "Most recent" therefore orders by (date, run_id or "") rather than date
    alone, so two runs on one date resolve deterministically to the later one.
    A legacy record has no run_id and sorts as "" — before any real run_id on
    the same date, which is the right precedence for a pre-#1542 section.

    An ok record missing any of the 5 score axes is skipped as a baseline — an
    old pre-`development` record carries only 4 axes, a different total scale,
    so folding it in would corrupt the Δ; skipping is a one-time Δ reset to –.
    The same guard also catches a malformed CURRENT compose that drops an axis
    (the two are indistinguishable here), so the warning names both causes.
    The skips are AGGREGATED into a single summary stderr line for the whole
    run (rather than one line per record) so a journal full of legacy 4-axis
    entries does not flood stderr on every nightly append.
    """
    best = {}  # id -> ((date, run_id), scores)
    skipped = 0
    for blob in AUDIT_DATA_RE.findall(journal_text):
        try:
            data = json.loads(blob)
        except json.JSONDecodeError:
            continue
        if data.get("model") != model:
            continue
        date = data.get("date", "")
        run_id = data.get("run_id") or ""
        if date == exclude_date and run_id == exclude_run_id:
            continue
        key = (date, run_id)
        for sid, rec in (data.get("scenarios") or {}).items():
            if rec.get("status") != "ok":
                continue
            scores = {k: rec.get(k) for k in SCORE_KEYS if rec.get(k) is not None}
            if len(scores) < len(SCORE_KEYS):
                skipped += 1
                continue
            if sid not in best or key > best[sid][0]:
                best[sid] = (key, scores)
    if skipped:
        # Keep the exact substring "missing score axes" — the self-test greps
        # for it.
        print(f"append_audit: {skipped} prior record(s) skipped as baselines "
              "— missing score axes (legacy pre-development entries or a "
              "malformed compose; Δ resets to –)", file=sys.stderr)
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
    # `run_id` rides alongside `date` so a reader can tell two same-date runs
    # apart. select_inventory.py reads only `date`, so the extra key is inert
    # there — and AUDIT_DATA_RE, shared byte-for-byte with it, is unchanged.
    payload = {"date": results["date"], "run_id": results["run_id"],
               "model": results.get("model", "?"), "scenarios": scenarios}
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
                            results["date"], results["run_id"])
    this_run_ok = {s["id"]: s["scores"] for s in scenarios
                   if s.get("status") == "ok" and s.get("scores")}

    lines = [
        f"## {results['date']} — {results['run_id']}",
        "",
        f"Model: {results.get('model', '?')} | Scenarios: {len(scenarios)} "
        f"(ok {counts['ok']} / failed {counts['failed']} / "
        f"config_error {counts['config_error']})",
        "",
        audit_data_comment(results),
        "",
        "| id | name | channel | category | status | (a) | (b) | (c) "
        "| (d) development | (e) payoff | Δ | comment |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
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
            cell(scores.get("breakdown_free")),
            cell(scores.get("development")), cell(payoff_cell),
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
    run_id_err = validate_run_id(results.get("run_id"))
    if run_id_err:
        # The journal is the only durable record of a cycle's judging, so an
        # unattended run that trips this must be recoverable by hand — name the
        # file the operator has to edit and what to do to it.
        print(f"append_audit: {run_id_err}", file=sys.stderr)
        print(f"  add a `run_id` to {args.results} and re-run the append",
              file=sys.stderr)
        return 1

    with journal_lock(args.journal):
        return _append_locked(args, results)


def _append_locked(args, results):
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
    # body with any same-key section still present (prior_ok_scores excludes
    # that one key itself), THEN drop the old same-key section.
    section = render_section(results, body)

    # (date, run_id) idempotency: drop an existing section with the SAME key.
    # A legacy date-only `## <date>` heading cannot match this pattern, which
    # is what keeps pre-#1542 sections alive.
    pattern = re.compile(
        rf"^## {re.escape(results['date'])} — {re.escape(results['run_id'])}\n"
        r".*?(?=^## |\Z)",
        re.DOTALL | re.MULTILINE)
    body, replaced = pattern.subn("", body)
    if replaced:
        print(f"warning: replaced existing section for {results['date']} "
              f"— {results['run_id']}", file=sys.stderr)

    stripped = body.strip("\n")
    body = "\n\n" + section + "\n" + stripped + ("\n\n" if stripped else "\n")

    with open(args.journal, "w", encoding="utf-8") as f:
        f.write(head + SECTIONS_MARKER + body + PROMOTION_MARKER + footer)

    action = "replaced" if replaced else "appended"
    print(f"{action} section {results['date']} — {results['run_id']} "
          f"({len(results.get('scenarios', []))} scenario(s)) in {args.journal}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
