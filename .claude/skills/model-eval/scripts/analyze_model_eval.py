#!/usr/bin/env python3
"""Analyze one or more pastura-harness run JSONL logs for /model-eval metrics.

Purpose: aggregate scorecard-adjacent metrics (terminal status, attempts /
retries, inference counts, tokens/sec, language mismatches) across a batch of
harness run logs, without any Swift/xcresult tooling — stdlib-only so it runs
on ubuntu CI as well as the Mac harness host.

usage: analyze_model_eval.py <run1.jsonl> [<run2.jsonl> ...]

Each input is one harness run log (see
`tools/harness/Sources/PasturaHarnessKit/RunLog.swift`): a `run_start` line,
zero or more `event` lines, and (on a clean finish) a `run_end` line. Lines
are snake_case JSON (one object per line).

Output: a SINGLE JSON object on stdout:

{
  "runs": [
    {
      "file": "<basename>",
      "run_id": str | null, "scenario_id": str | null,
      "language": str | null, "model": str | null,   // from run_start
      "status": "ok" | "error" | "crashed",          // run_end.status, or
                                                      // "crashed" when
                                                      // run_end is absent or
                                                      // truncated (#253)
      "attempts": int | null,        // run_end.attempts (retry proxy)
      "duration_sec": float | null,  // run_end.duration_sec
      "inferences": int,             // count of inference_completed events
      "language_mismatches": int,    // count of language_mismatch events
      "tokens": int, "gen_seconds": float,  // summed over inference_completed
                                             // events carrying BOTH
                                             // token_count and
                                             // duration_seconds
      "tok_per_sec": float | null,   // tokens / gen_seconds, null if 0
      "skipped_lines": int           // unparseable / truncated lines
    }, ...
  ],
  "aggregate": {
    "runs_total": int, "runs_ok": int, "runs_failed": int,  // error+crashed
    "attempts_total": int,
    "attempts_mean": float | null,  // mean attempts per run that reported
                                    // one; the retry-rate proxy (see below)
    "inferences_total": int,
    "language_mismatch_total": int,
    "tok_per_sec_overall": float | null  // sum(tokens) / sum(gen_seconds)
  }
}

Retry proxy, explicitly: harness JSONL logs do NOT carry JSON-repair
diagnostics (the LLMCaller-level retry-on-malformed-output path) — only
`run_end.attempts` (1 on first-try success, 2 after the Engine-level retry)
is present. `attempts_mean` is therefore the only retry signal available
here, not a repair-count; a future JSON-repair counter is out of scope.
"""

import json
import os
import sys

def analyze_run(path):
    """Parse one run log into a single metrics dict. Never raises on
    malformed/truncated JSONL content — unparseable lines are skipped and
    tallied in `skipped_lines`."""
    run_start = None
    run_end = None
    inferences = 0
    language_mismatches = 0
    tokens = 0
    gen_seconds = 0.0
    skipped_lines = 0

    with open(path, encoding="utf-8") as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                # Truncated last line (interrupted run) or otherwise
                # corrupt — count and move on, never raise.
                skipped_lines += 1
                continue
            if not isinstance(obj, dict):
                skipped_lines += 1
                continue
            kind = obj.get("type")
            if kind == "run_start":
                if run_start is None:
                    run_start = obj
            elif kind == "run_end":
                run_end = obj
            elif kind == "event":
                ev = obj.get("event")
                if ev == "inference_completed":
                    inferences += 1
                    tc = obj.get("token_count")
                    ds = obj.get("duration_seconds")
                    if tc is not None and ds is not None:
                        tokens += tc
                        gen_seconds += ds
                elif ev == "language_mismatch":
                    language_mismatches += 1
            # Unknown/other "type" values are ignored (not skipped_lines —
            # they parsed fine, just aren't relevant to this analysis).

    if run_end is not None:
        status = run_end.get("status") or "crashed"
        attempts = run_end.get("attempts")
        duration_sec = run_end.get("duration_sec")
    else:
        # No run_end line at all — the run crashed or was interrupted before
        # it could write the summary line (#253 pattern).
        status = "crashed"
        attempts = None
        duration_sec = None

    return {
        "file": os.path.basename(path),
        "run_id": run_start.get("run_id") if run_start else None,
        "scenario_id": run_start.get("scenario_id") if run_start else None,
        "language": run_start.get("language") if run_start else None,
        "model": run_start.get("model") if run_start else None,
        "status": status,
        "attempts": attempts,
        "duration_sec": duration_sec,
        "inferences": inferences,
        "language_mismatches": language_mismatches,
        "tokens": tokens,
        "gen_seconds": gen_seconds,
        "tok_per_sec": (tokens / gen_seconds) if gen_seconds > 0 else None,
        "skipped_lines": skipped_lines,
    }


def build_aggregate(runs):
    runs_total = len(runs)
    runs_ok = sum(1 for r in runs if r["status"] == "ok")
    runs_failed = runs_total - runs_ok

    attempts_vals = [r["attempts"] for r in runs if r["attempts"] is not None]
    attempts_total = sum(attempts_vals)
    attempts_mean = (attempts_total / len(attempts_vals)) if attempts_vals else None

    inferences_total = sum(r["inferences"] for r in runs)
    language_mismatch_total = sum(r["language_mismatches"] for r in runs)

    tokens_total = sum(r["tokens"] for r in runs)
    gen_seconds_total = sum(r["gen_seconds"] for r in runs)
    tok_per_sec_overall = (
        tokens_total / gen_seconds_total if gen_seconds_total > 0 else None
    )

    return {
        "runs_total": runs_total,
        "runs_ok": runs_ok,
        "runs_failed": runs_failed,
        "attempts_total": attempts_total,
        "attempts_mean": attempts_mean,
        "inferences_total": inferences_total,
        "language_mismatch_total": language_mismatch_total,
        "tok_per_sec_overall": tok_per_sec_overall,
    }


def main(argv):
    if len(argv) < 2:
        print(
            "usage: analyze_model_eval.py <run1.jsonl> [<run2.jsonl> ...]",
            file=sys.stderr,
        )
        return 2

    runs = []
    for path in argv[1:]:
        try:
            runs.append(analyze_run(path))
        except OSError as e:
            print(f"analyze_model_eval: cannot read {path}: {e}", file=sys.stderr)
            return 2

    output = {"runs": runs, "aggregate": build_aggregate(runs)}
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
