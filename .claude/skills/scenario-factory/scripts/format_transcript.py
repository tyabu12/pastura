#!/usr/bin/env python3
"""JSONL run log -> markdown transcript for the in-session judge.

usage: format_transcript.py <run.jsonl>

Tolerates the #253 crash shape: unparseable lines (e.g. a truncated final
line from a mid-write SIGABRT) are skipped and counted, and a missing
run_end is reported in the Result section instead of raising. Inference
progress events are omitted as judge-irrelevant noise.
"""

import json
import sys

# Noise for a quality judgement; timings live in the raw JSONL if needed.
SKIPPED_EVENTS = {"inference_started", "inference_completed"}


def fmt_scores(scores):
    return ", ".join(f"{k}: {v}" for k, v in sorted(scores.items()))


def render_event(line, out):
    event = line.get("event", "?")
    if event in SKIPPED_EVENTS:
        return
    if event == "round_started":
        out.append(f"\n### Round {line.get('round')}/{line.get('total_rounds')}\n")
    elif event == "round_completed":
        out.append(f"[round_completed] scores: {fmt_scores(line.get('scores', {}))}")
    elif event in ("phase_started", "phase_completed"):
        pass  # phase boundaries are implied by the outputs themselves
    elif event == "agent_output":
        fields = line.get("fields") or {}
        out.append(f"**{line.get('agent')}** ({line.get('phase_type')}):")
        # statement first — it is the user-visible utterance.
        for key in sorted(fields, key=lambda k: (k != "statement", k)):
            out.append(f"- {key}: {fields[key]}")
        if not fields and line.get("raw_text"):
            out.append(f"- raw_text: {line['raw_text']}")
        out.append("")
    elif event == "assignment":
        out.append(f"[assignment] {line.get('agent')} ← {line.get('value')}")
    elif event == "vote_results":
        votes = line.get("votes", {})
        tallies = line.get("tallies", {})
        vote_str = ", ".join(f"{k}→{v}" for k, v in sorted(votes.items()))
        out.append(f"[vote_results] {vote_str} | tallies: {fmt_scores(tallies)}")
    elif event == "score_update":
        out.append(f"[score_update] {fmt_scores(line.get('scores', {}))}")
    elif event == "summary":
        out.append(f"[summary] {line.get('value')}")
    elif event == "pairing_result":
        out.append(
            f"[pairing] {line.get('agent')}({line.get('action1')}) vs "
            f"{line.get('agent2')}({line.get('action2')})")
    elif event == "elimination":
        out.append(
            f"[elimination] {line.get('agent')} ({line.get('vote_count')} votes)")
    elif event == "language_mismatch":
        out.append(
            f"[language_mismatch] {line.get('agent')}: detected "
            f"{line.get('detected')}, expected {line.get('expected')}")
    elif event == "error":
        out.append(f"⚠ [error] {line.get('error')}")
    elif event == "simulation_completed":
        pass  # run_end carries the outcome
    else:
        out.append(f"[{event}] {json.dumps(line, ensure_ascii=False)}")


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path = sys.argv[1]

    run_start = None
    run_end = None
    events = []
    skipped = 0
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    line = json.loads(raw)
                except json.JSONDecodeError:
                    skipped += 1
                    continue
                kind = line.get("type")
                if kind == "run_start":
                    run_start = line
                elif kind == "run_end":
                    run_end = line
                elif kind == "event":
                    events.append(line)
    except OSError as e:
        print(f"cannot read {path}: {e}", file=sys.stderr)
        return 2

    out = []
    if run_start:
        out.append(
            f"# {run_start.get('scenario_name')} "
            f"({run_start.get('scenario_id')}) — run {run_start.get('run_id')}")
        out.append(
            f"- date: {run_start.get('date')} | language: "
            f"{run_start.get('language')} | model: {run_start.get('model')} | "
            f"timeout: {run_start.get('timeout_sec')}s | est. inferences: "
            f"{run_start.get('estimated_inferences')}")
    else:
        out.append(f"# (run_start missing) — {path}")

    current_attempt = None
    for line in events:
        attempt = line.get("attempt")
        if attempt != current_attempt:
            current_attempt = attempt
            out.append(f"\n## Attempt {attempt}\n")
        render_event(line, out)

    out.append("\n## Result\n")
    if run_end:
        out.append(
            f"status={run_end.get('status')} attempts={run_end.get('attempts')} "
            f"duration={run_end.get('duration_sec')}s")
        if run_end.get("error"):
            out.append(f"error: {run_end['error']}")
    else:
        out.append(
            f"⚠ run_end missing — process died mid-run (#253). "
            f"{len(events)} event(s) captured before death.")
    if skipped:
        out.append(f"\n_({skipped} unparseable line(s) skipped)_")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
