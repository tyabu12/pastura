#!/usr/bin/env python3
"""ADR-022 §D4 (P8) — demo-replay event-coverage gate (fail-closed).

Cross-checks that every `SimulationEvent` name the harness emits to JSONL
(the `event: "…"` string literals in `EventLineMapper.swift`, the real JSONL
emit surface) is classified in `jsonl_to_demo_replay.py`'s `HANDLED_EVENTS`
or `IGNORED_EVENTS`. An emit literal in neither set means the converter would
silently drop (or now hard-error on) an event the demo pipeline never decided
about — exactly the P8 drift this gate closes.

This is the gate LOGIC (analogue of `scripts/p8-precommit-gate.sh`); the
tripwire structure that exercises it against synthetic fixtures + the real
files lives in `scripts/tests/demo-replay-event-coverage-test.sh` (the CI
"Shell gate tests" job). Anchoring on the emit literals — not snake_cased
`SimulationEvent` case names — avoids a hand-maintained alias map and any
`SimulationError` contamination (ADR-022 §D4). The two events the mapper maps
to no line (`agentOutputStream`, `roundCheckpoint`) never reach JSONL and are
covered by the P3 `swift build` canary, so they need no entry here.

Fail-closed by design (unlike the fail-open `gallery_census.py`): any
uncovered emit literal, any HANDLED∩IGNORED overlap, or an extracted count
below `--min-events` exits non-zero. The count-floor pins against a regex that
silently under-extracts (e.g. after an `EventLine` construction reshape).

usage:
  check_demo_replay_event_coverage.py [--mapper PATH] [--converter PATH]
                                      [--min-events N]
Defaults point at the real files; the shell gate overrides both paths to run
synthetic drift / floor fixtures.
"""
import argparse
import importlib.util
import re
import sys

# The `event: "…"` emit literals in EventLineMapper.swift. `event:` is the
# EventLine initializer's argument label; the only quoted-string values it
# takes are the JSONL event names (lowercase snake_case). The `func map(_
# event: SimulationEvent …)` parameter is `event:` followed by a type, not a
# quoted string, so it does not match.
_EMIT_RE = re.compile(r'event:\s*"([a-z0-9_]+)"')

_DEFAULT_MAPPER = "tools/harness/Sources/PasturaHarnessKit/EventLineMapper.swift"
_DEFAULT_CONVERTER = "scripts/jsonl_to_demo_replay.py"


def extract_emit_literals(mapper_path):
    """The set of `event: "…"` literals declared in the mapper source."""
    with open(mapper_path, encoding="utf-8") as f:
        return set(_EMIT_RE.findall(f.read()))


def load_classification(converter_path):
    """Import the converter by file path and return (HANDLED, IGNORED) sets.

    `spec_from_file_location` loads an arbitrary path (the temp fixtures the
    shell gate writes live outside the module search path, so `import_module`
    can't reach them). Importing runs the converter's top-level defs but NOT
    `main()` (guarded by `if __name__ == "__main__"`), so it has no side
    effect beyond its own imports.
    """
    spec = importlib.util.spec_from_file_location("converter_under_test", converter_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"check_demo_replay_event_coverage: cannot load {converter_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    try:
        return set(module.HANDLED_EVENTS), set(module.IGNORED_EVENTS)
    except AttributeError as exc:
        raise SystemExit(
            f"check_demo_replay_event_coverage: {converter_path} is missing "
            f"HANDLED_EVENTS/IGNORED_EVENTS ({exc})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mapper", default=_DEFAULT_MAPPER)
    parser.add_argument("--converter", default=_DEFAULT_CONVERTER)
    parser.add_argument(
        "--min-events", type=int, default=0,
        help="count-floor: fail if fewer emit literals are extracted (guards "
             "against regex under-extraction). Real-file floor is set by the "
             "shell gate; bump it when EventLineMapper gains an emit literal.")
    args = parser.parse_args()

    emits = extract_emit_literals(args.mapper)
    handled, ignored = load_classification(args.converter)

    errors = []

    if len(emits) < args.min_events:
        errors.append(
            f"extracted {len(emits)} emit literal(s) from {args.mapper}, below "
            f"the --min-events floor of {args.min_events}. The regex likely "
            "under-extracted (EventLine construction reshaped?) — or an event "
            "was removed; update the floor if the removal is intended.")

    overlap = handled & ignored
    if overlap:
        errors.append(
            "these events are in BOTH HANDLED_EVENTS and IGNORED_EVENTS "
            f"(must be exactly one): {', '.join(sorted(overlap))}")

    uncovered = emits - handled - ignored
    if uncovered:
        errors.append(
            "these emitted event(s) are classified in NEITHER HANDLED_EVENTS "
            f"nor IGNORED_EVENTS: {', '.join(sorted(uncovered))}. Add each to "
            "one of the two sets in the converter (ADR-022 §D4).")

    if errors:
        print(f"check_demo_replay_event_coverage: FAIL ({args.mapper})", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        f"check_demo_replay_event_coverage: OK — {len(emits)} emit literal(s), "
        f"all classified ({len(handled)} handled / {len(ignored)} ignored).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
