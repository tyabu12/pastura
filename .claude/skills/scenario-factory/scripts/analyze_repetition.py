#!/usr/bin/env python3
"""Anti-repetition A/B analyzer for pastura-harness JSONL run logs (#1105).

usage:
  analyze_repetition.py --arm NAME run1.jsonl [run2.jsonl ...] \\
                        [--arm NAME2 ...] [--field statement]

Compares one or more *arms* (each = a set of harness run logs) on the
repetition metrics that motivated the #1105 DRY anti-repetition sampler,
plus safety gauges so a repetition win isn't bought with a coherence /
throughput / parse-rate regression.

Metrics per arm (mean across the arm's runs):

  own-pair self-echo   Primary. For each agent, char-3gram Jaccard between
                       its consecutive `--field` statements (default
                       `statement`). This is the register-dominant cross-round
                       verbatim echo the DRY seed targets — an agent parroting
                       its own prior line. Lower = less self-repetition.
  exact self-echo      Count of byte-identical consecutive same-agent
                       statements (the worst case; DRY should drive this to 0).
  cross-agent          Secondary. Mean pairwise char-3gram Jaccard among
                       different agents' statements within the same
                       (round, phaseType) group — template collapse.

Safety gauges per arm (a No-Go signal if the DRY arm regresses these):

  retries              Retry-pressure proxy = completed inferences minus turns
                       that produced an agent_output or were skipped. Each
                       parse/empty/language retry adds an extra
                       inference_completed with no matching agent_output. (The
                       JSONL `attempt` field is the RUN-level counter, 1..2, so
                       it can't be used here — see the inline note in
                       `analyze_run`.)
  errors               `error` + `turn_skipped` event lines.
  tok/s                Aggregate completion tokens / inference seconds.
  DRY fired            If a sibling `<run>.log` exists, the `[#1105 DRY]`
                       stderr probe lines are counted + total seeded tokens
                       summed, confirming the sampler actually engaged in the
                       arm (a null result on an arm that never seeded is
                       meaningless).

Coherence (paraphrase-collapse / language drift) is NOT auto-scored — read
the transcripts (scripts/format_transcript.py) alongside these numbers.

Deterministic, stdlib-only. Reads `.jsonl`; the flat EventLine schema is
produced by PasturaHarnessKit/EventLineMapper.swift.
"""

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def char_3grams(text):
    """Set of char 3-grams over whitespace-collapsed text."""
    norm = " ".join(text.split())
    if len(norm) < 3:
        return {norm} if norm else set()
    return {norm[i : i + 3] for i in range(len(norm) - 2)}


def jaccard(a, b):
    ga, gb = char_3grams(a), char_3grams(b)
    if not ga and not gb:
        return 0.0
    union = ga | gb
    return len(ga & gb) / len(union) if union else 0.0


def load_lines(path):
    lines = []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                lines.append(json.loads(raw))
            except json.JSONDecodeError:
                # A truncated final line (killed run) shouldn't abort analysis.
                continue
    return lines


def analyze_run(path, field):
    """Return per-run metrics dict for one JSONL log."""
    lines = load_lines(path)

    # Ordered statements per agent (in transcript order).
    per_agent = defaultdict(list)
    # (round, phaseType) -> list of statements from distinct agents.
    per_group = defaultdict(list)
    cur_round = 0
    errors = 0
    tokens = 0
    seconds = 0.0
    n_inference = 0
    n_output = 0
    n_skipped = 0

    # JSONL keys are snake_case (PasturaHarnessKit EventLine coding keys):
    # `phase_type`, `duration_seconds`, `token_count`. The `attempt` field is
    # RUN-level (always 1 on a first-try run), NOT a per-inference retry — so
    # retry pressure is derived as (inferences that completed) minus (turns
    # that produced an agent_output or were skipped): each parse/empty/lang
    # retry adds an extra inference_completed with no matching agent_output.
    for ln in lines:
        event = ln.get("event")
        if event == "round_started":
            cur_round = ln.get("round", cur_round)
        elif event in ("error", "turn_skipped"):
            errors += 1
            if event == "turn_skipped":
                n_skipped += 1
        elif event == "inference_completed":
            n_inference += 1
            tc = ln.get("token_count")
            ds = ln.get("duration_seconds")
            if isinstance(tc, int) and isinstance(ds, (int, float)) and ds > 0:
                tokens += tc
                seconds += ds
        elif event == "agent_output":
            n_output += 1
            fields = ln.get("fields") or {}
            value = fields.get(field)
            if not isinstance(value, str) or not value.strip():
                continue
            agent = ln.get("agent", "?")
            per_agent[agent].append(value)
            phase = ln.get("phase_type", "?")
            per_group[(cur_round, phase)].append(value)

    retries = max(0, n_inference - n_output - n_skipped)

    # Own-pair self-echo: consecutive same-agent statements.
    self_jaccs = []
    exact_echoes = 0
    for stmts in per_agent.values():
        for prev, nxt in zip(stmts, stmts[1:]):
            self_jaccs.append(jaccard(prev, nxt))
            if " ".join(prev.split()) == " ".join(nxt.split()):
                exact_echoes += 1

    # Cross-agent: pairwise within each (round, phase) group of >=2 statements.
    cross_jaccs = []
    for stmts in per_group.values():
        for i in range(len(stmts)):
            for j in range(i + 1, len(stmts)):
                cross_jaccs.append(jaccard(stmts[i], stmts[j]))

    seeded_tokens, seed_events = seed_probe(path)

    return {
        "self_pairs": len(self_jaccs),
        "self_echo": mean(self_jaccs),
        "exact_echoes": exact_echoes,
        "cross_pairs": len(cross_jaccs),
        "cross_echo": mean(cross_jaccs),
        "retries": retries,
        "errors": errors,
        "tok_s": (tokens / seconds) if seconds > 0 else 0.0,
        "seeded_tokens": seeded_tokens,
        "seed_events": seed_events,
    }


def seed_probe(jsonl_path):
    """Count `[#1105 DRY]` stderr probe lines in a sibling `.log`, if present.

    Returns (total_seeded_tokens, seed_event_count). (0, 0) when no log or no
    probe lines — which for a DRY arm means the sampler never fired.
    """
    log_path = Path(str(jsonl_path).rsplit(".jsonl", 1)[0] + ".log")
    if not log_path.exists():
        return 0, 0
    total = 0
    events = 0
    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "[#1105 DRY] seeded" in raw:
            events += 1
            # "[#1105 DRY] seeded 7 tok / 1 seed(s) ..."
            parts = raw.split("seeded", 1)[1].split("tok", 1)[0].strip()
            try:
                total += int(parts)
            except ValueError:
                pass
    return total, events


def mean(values):
    return sum(values) / len(values) if values else 0.0


def aggregate(runs):
    keys = [
        "self_echo",
        "exact_echoes",
        "cross_echo",
        "retries",
        "errors",
        "tok_s",
        "seeded_tokens",
        "seed_events",
    ]
    return {k: mean([r[k] for r in runs]) for k in keys}


def main():
    parser = argparse.ArgumentParser(description="Anti-repetition A/B analyzer (#1105)")
    parser.add_argument(
        "--arm",
        action="append",
        nargs="+",
        metavar=("NAME", "RUN.jsonl"),
        required=True,
        help="An arm: a label followed by one or more JSONL run logs.",
    )
    parser.add_argument(
        "--field",
        default="statement",
        help="Output field to measure repetition on (default: statement).",
    )
    args = parser.parse_args()

    arm_results = {}
    for arm in args.arm:
        if len(arm) < 2:
            print(f"error: arm '{arm[0]}' has no run files", file=sys.stderr)
            return 2
        name, files = arm[0], arm[1:]
        runs = []
        for f in files:
            if not Path(f).exists():
                print(f"error: run log not found: {f}", file=sys.stderr)
                return 2
            runs.append(analyze_run(f, args.field))
        arm_results[name] = (aggregate(runs), len(runs))

    print(f"# Anti-repetition A/B — field=`{args.field}`\n")
    header = (
        f"{'arm':<12} {'runs':>4} {'self-echo':>10} {'exact':>6} "
        f"{'cross':>7} {'retries':>8} {'errors':>7} {'tok/s':>7} "
        f"{'seed-tok':>9} {'seed-ev':>8}"
    )
    print(header)
    print("-" * len(header))
    for name, (agg, n) in arm_results.items():
        print(
            f"{name:<12} {n:>4} {agg['self_echo']:>10.3f} "
            f"{agg['exact_echoes']:>6.1f} {agg['cross_echo']:>7.3f} "
            f"{agg['retries']:>8.1f} {agg['errors']:>7.1f} {agg['tok_s']:>7.1f} "
            f"{agg['seeded_tokens']:>9.0f} {agg['seed_events']:>8.1f}"
        )
    print(
        "\n(self-echo/cross = mean char-3gram Jaccard, lower=less repetition; "
        "exact = identical consecutive same-agent statements; seed-* confirm "
        "the DRY sampler fired. Read transcripts for coherence.)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
