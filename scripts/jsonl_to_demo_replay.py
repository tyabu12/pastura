#!/usr/bin/env python3
"""Convert a pastura-harness run JSONL into a DL-time demo-replay YAML.

This is the curator tool behind the "exporter-captured demos" long-term
plan (demo-replay-spec.md §6): instead of hand-authoring demo YAMLs, run a
scenario through `pastura-harness` (ADR-013, real local Gemma inference),
pick the best transcript, and convert it here.

Output schema: demo-replay-spec.md §3.2 (schema_version=2, preset_ref,
metadata, turns, code_phase_events). Field selection mirrors
`Pastura/Pastura/App/YAMLReplayExporter.swift`; payload `kind`
discriminators match `YAMLReplaySource.decodePayloadStanza`.

Mapping:
  - `agent_output`  -> `turns[]`            (statement/inner_thought or vote/reason)
  - `shared_assignment` -> one `sharedAssignment` code-phase event (assign
                       target: all — the round's shared お題; value only, no agent)
  - `assignment`    -> one `assignment` code-phase event per agent (assign
                       target: random_one — word wolf, each agent's own secret)
  - `vote_results`  -> `voteResults`
  - `score_update`  -> `scoreUpdate`
  - `elimination`   -> `elimination`
  - `summary`       -> `summary`
  - `event_injected`-> `eventInjected`
  - `pairing_result`-> `pairingResult`
Phase coordinates (settled by #1505; spec §3.2 is the authority):
`phase_path` is written verbatim from `phase_started.phase_path`, `phase_index`
is `phase_path[0]`, and `phase_type` names the LEAF phase. A branch sub-phase
therefore records `[i, j]` and a `phase_type` that does NOT equal
`phases[phase_index].type` — the enclosing `conditional`'s. That asymmetry is
the point; `BundledDemoReplaySourceTests.assertPhaseAlignment` is the sole owner
of checking it (spec §3.3), not this script and not the runtime loader.

`branch` is resolved here and only here. `[i, j]` cannot say whether `then[j]`
or `else[j]` ran — they carry the identical path — so the branch comes from the
`conditional_evaluated` the harness emits between the conditional's own
`phase_started` and its branch's. `YAMLReplayExporter` cannot supply it (no
column persists the branch), which is why the field is optional rather than
required. The resolver mirrors `gallery_highlight_extract.annotate`, whose
prose has the fuller derivation. It diverges where that tool's target
coordinate system does: `annotate` resolves each path against the scenario's
phase tree, so it reads the open conditional from `nodes[...].type` AND range-
checks the branch index. This script emits the path verbatim, so it reads the
open conditional from the transcript's own `phase_type` — a curator's job is to
record what the transcript says, and the minimal preset it is handed need not
carry `phases:` at all — and it range-checks nothing. The gate owns that:
`conditionalDiagnostic` indexes the branch at the path's second component and
refuses an index no branch holds. Note the ownership is the GATE's, not this
script's `branch` field — an earlier revision of this paragraph reasoned that a
depth-2 path always carries a `branch` here and stopped there, which left the
range case unowned for `YAMLReplayExporter`, the writer that emits a nested
path and can never emit a branch.

Recapture workflow (full demo-set swap):
  1. Run each scenario N times through the harness:
       bash .claude/skills/scenario-factory/scripts/run_scenario.sh \
         <scenario.yaml> ~/Models/gemma-4-E2B-it-Q4_K_M.gguf <out.jsonl> 900
  2. Read transcripts via scenario-factory/scripts/format_transcript.py and
     pick the best run per scenario (ja and en field-tested separately).
  3. Place the demo-backing preset under Resources/DemoPresets/ FIRST
     (sha is computed from the on-disk preset bytes), then convert:
       python3 scripts/jsonl_to_demo_replay.py <run.jsonl> \
         Pastura/Pastura/Resources/DemoPresets/<id>.yaml \
         Pastura/Pastura/Resources/DemoReplays/<id>_demo.yaml --language ja
  4. Audit fields.* / code_phase_events[].summary against
     Resources/ContentBlocklist.json (outputPatterns; ADR-005 §5.2), then
     re-run with --filter-applied to attest content_filter_applied: true.
  5. Verify: python3 scripts/check_demo_replay_drift.py

Usage:
  jsonl_to_demo_replay.py <run.jsonl> <preset.yaml> <out.yaml> \
      [--language ja|en] [--filter-applied]
"""
import argparse
import hashlib
import json

import yaml  # PyYAML — reads preset name/description, writes the demo YAML

# event_name -> CodePhaseEventPayload `kind` discriminator
CODE_KIND = {
    "vote_results": "voteResults",
    "score_update": "scoreUpdate",
    "elimination": "elimination",
    "summary": "summary",
    "event_injected": "eventInjected",
    "pairing_result": "pairingResult",
}

# ADR-022 §D4 (P8) — the forced-decision contract for this non-Swift consumer.
# Every event name EventLineMapper.swift emits to JSONL must be classified in
# exactly one of these two sets:
#   HANDLED_EVENTS — drives a turn or a code-phase event in the demo output.
#   IGNORED_EVENTS — reaches JSONL but is deliberately dropped from the demo
#                    (lifecycle / diagnostic events the replay schema has no
#                    slot for; moving one here is a reviewed diff).
# NOTE the set means "not EMITTED", not "not READ". `conditional_evaluated` sits
# in IGNORED_EVENTS and yet drives `branch` resolution below — the demo schema
# has no slot for the event itself, but the verdict it carries is the only
# source for which branch ran. Adding a read of an ignored event is fine; what
# the classification forbids is emitting one without a reviewed diff.
# An event in NEITHER set is a HARD ERROR at convert time (see the guard in
# `main`) — previously a silent drop with no failure mode at all. The
# `scripts/tests/demo-replay-event-coverage-test.sh` shell gate cross-checks
# this classification against the Swift emit surface so the two never diverge.
HANDLED_EVENTS = {
    "round_started",
    "phase_started",
    "agent_output",
    "shared_assignment",
    "assignment",
} | set(CODE_KIND)

IGNORED_EVENTS = {
    "round_completed",
    "phase_completed",
    "relationship_update",  # raw affinity matrix (#910); demo/replay drops it
    "narration",  # live commentary (#909); curated demos don't use narrate yet
    # — teletop demo integration is a follow-up. Reviewed drop per ADR-022 §D4.
    "conditional_evaluated",  # read for `branch` (see note above), never emitted
    "simulation_completed",
    "simulation_paused",
    "error",
    "inference_started",
    "inference_completed",
    "language_mismatch",
    "turn_skipped",
    "action_rejected",  # off-menu choose action dropped (ADR-021 §Amendment
    # 2026-07-17); live-only degradation signal, same as turn_skipped — a
    # curated demo cannot regenerate it, so it never reaches the replay.
}

# Stable field order for turn `fields` (mirrors existing hand-authored demos:
# statement before inner_thought, vote before reason). Unknown keys keep
# their source order after these.
FIELD_ORDER = ["statement", "inner_thought", "action", "vote", "reason"]


class FlowList(list):
    """A list rendered inline (`[1, 0]`) rather than as a block sequence.

    Only `phase_path` uses it, so it matches the spec §3.2 example and
    `YAMLReplayExporter.yamlIntArray` — the shipped demos are curator-produced,
    so without this the example would describe only the writer whose output
    never ships. Both renderings parse identically; this is legibility.

    Deliberately NOT `default_flow_style=None` on the dump: that switch reaches
    every leaf collection, which folds `metadata` and each turn's `fields` into
    one-line mappings too. `fields.*` is what the spec §3.4 content audit is
    read against by hand, so that is a real cost for an unrelated gain.
    """


yaml.add_representer(
    FlowList,
    lambda dumper, data: dumper.represent_sequence(
        "tag:yaml.org,2002:seq", data, flow_style=True),
    Dumper=yaml.SafeDumper)


def sha256_hex(path):
    # Mirror ReplayHashing.sha256Hex / check_demo_replay_drift.sha256_hex:
    # decode as UTF-8 text, re-encode to UTF-8 bytes, then hash.
    text = open(path, encoding="utf-8").read()
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def ordered_fields(fields):
    keys = sorted(
        fields.keys(),
        key=lambda k: (FIELD_ORDER.index(k) if k in FIELD_ORDER else len(FIELD_ORDER), k),
    )
    return {k: fields[k] for k in keys}


def code_summary(ev):
    e = ev["event"]
    if e == "score_update":
        return "Scores — " + ", ".join(f"{k}: {v}" for k, v in ev["scores"].items())
    if e == "vote_results":
        return "Votes — " + ", ".join(f"{k}: {v}" for k, v in ev.get("tallies", {}).items())
    if e == "elimination":
        return f"{ev['agent']} eliminated ({ev.get('vote_count', '?')} votes)"
    if e == "summary":
        return (ev.get("value") or "").strip()
    if e == "event_injected":
        return f"Event: {ev.get('value', '')}"
    if e == "pairing_result":
        return (f"{ev.get('agent')}({ev.get('action1')}) vs "
                f"{ev.get('agent2')}({ev.get('action2')})")
    return e


def code_payload(ev):
    e = ev["event"]
    kind = CODE_KIND[e]
    if e == "score_update":
        return {"kind": kind, "scores": dict(ev["scores"])}
    if e == "vote_results":
        return {"kind": kind, "votes": dict(ev.get("votes", {})),
                "tallies": dict(ev.get("tallies", {}))}
    if e == "elimination":
        return {"kind": kind, "agent": ev["agent"], "vote_count": ev.get("vote_count", 0)}
    if e == "event_injected":
        return {"kind": kind, "event": ev.get("value", "")}
    if e == "pairing_result":
        # The harness EventLine names agent1 `agent`; agent2/action1/action2
        # keep their names. decodePairingResult requires agent1+agent2 (throws
        # otherwise), so populate all four — a bare {kind} would silent-skip a
        # pairing-based demo (e.g. prisoner's-dilemma) at load.
        return {"kind": kind,
                "agent1": ev.get("agent", ""), "action1": ev.get("action1", ""),
                "agent2": ev.get("agent2", ""), "action2": ev.get("action2", "")}
    return {"kind": kind}  # summary carries no structured payload


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("preset")
    ap.add_argument("out")
    ap.add_argument("--language", default=None)
    ap.add_argument("--filter-applied", action="store_true")
    a = ap.parse_args()

    lines = [json.loads(l) for l in open(a.run, encoding="utf-8") if l.strip()]
    start = next(l for l in lines if l.get("type") == "run_start")
    preset = yaml.safe_load(open(a.preset, encoding="utf-8"))

    turns, code = [], []
    # `phase_path_cur` starts None, not [0]: an event reaching the emit sites
    # below before the first `phase_started` has no coordinate, and 0 would be
    # the same invention the `phase_path` guard refuses — removed from one
    # source only, it would survive here. (`round_no` is left at 0: nothing here
    # has measured what a round-0 turn does downstream.)
    round_no, phase_path_cur, phase_type_cur = 0, None, ""
    branch_cur = None        # "then" / "else" while inside a branch sub-phase
    open_conditional = None  # top-level index of the conditional in flight
    pending_branch = None    # (top, "then"/"else") from the last verdict

    def emitted_coords():
        """The current phase's coordinate fields, or refuse. Reads live state."""
        if phase_path_cur is None:
            raise SystemExit(
                f"jsonl_to_demo_replay: an event in {a.run} precedes the first "
                "`phase_started`, so phase_index cannot be derived.")
        # `phase_index` is `phase_path[0]` BY DEFINITION (spec §3.2) — it is
        # emitted rather than dropped because it stays required in v2, so a
        # reader that predates `phase_path` still orders correctly.
        coords = {"phase_index": phase_path_cur[0],
                  "phase_path": FlowList(phase_path_cur)}
        if branch_cur is not None:
            coords["branch"] = branch_cur
        return coords

    for l in lines:
        if l.get("type") != "event":
            continue
        e = l.get("event")
        # ADR-022 §D4 (P8) — force a classification decision. An event name in
        # neither set is a hard error (was: silent drop). The guard sits after
        # the `type != event` filter so lifecycle lines (run_start/run_end,
        # which carry no `event` field) never reach it.
        if e not in HANDLED_EVENTS and e not in IGNORED_EVENTS:
            raise SystemExit(
                f"jsonl_to_demo_replay: unknown event {e!r} in {a.run}. Add it "
                "to HANDLED_EVENTS or IGNORED_EVENTS (did EventLineMapper's "
                "emit surface change?) — see ADR-022 §D4.")
        if e == "round_started":
            round_no = l["round"]
        elif e == "conditional_evaluated":
            # Ignored for emission, read for `branch` — see the IGNORED_EVENTS
            # note. Both refusals below are fatal: an invented branch would be
            # indistinguishable from a measured one in the shipped demo.
            if open_conditional is None:
                raise SystemExit(
                    f"jsonl_to_demo_replay: a `conditional_evaluated` in {a.run} "
                    "has no preceding `phase_started` of type `conditional`, so "
                    "the branch it decides cannot be attributed to a phase.")
            result = l.get("result")
            if not isinstance(result, bool):
                raise SystemExit(
                    f"jsonl_to_demo_replay: a `conditional_evaluated` in {a.run} "
                    f"carries result {result!r}, not a boolean; the taken branch "
                    "cannot be derived from it.")
            pending_branch = (open_conditional, "then" if result else "else")
        elif e == "phase_started":
            # Track the path and the phase_type of the current phase. Code-phase
            # events (vote_results / score_update / summary / event_injected)
            # carry NO phase_type of their own, so the demo's phase_type has to
            # come from the enclosing phase_started, not the event name.
            path = l.get("phase_path")
            if not isinstance(path, list) or not path:
                raise SystemExit(
                    f"jsonl_to_demo_replay: a `phase_started` in {a.run} carries "
                    "no usable `phase_path`, so phase_index cannot be derived.")
            if any(not isinstance(x, int) or isinstance(x, bool) for x in path):
                raise SystemExit(
                    f"jsonl_to_demo_replay: a `phase_started` in {a.run} carries "
                    f"`phase_path` {path} with a non-integer element; a bool "
                    "would resolve as 0/1 and name a phase the run never entered.")
            if len(path) > 2:
                raise SystemExit(
                    f"jsonl_to_demo_replay: a `phase_started` in {a.run} carries "
                    f"`phase_path` {path}, {len(path)} deep, but the engine's "
                    "depth-1 rule bounds it to 2 (ScenarioLoader.parsePhaseType "
                    "refuses a nested `conditional` at parse time). A deeper path "
                    "means the transcript and that rule disagree.")
            phase_type_cur = l.get("phase_type", "")
            if len(path) == 1:
                open_conditional = path[0] if phase_type_cur == "conditional" else None
                branch_cur = None
                # Cleared on EVERY top-level phase, conditional included: the
                # engine re-evaluates the condition once per round, so carrying
                # the previous round's verdict forward would resolve round N's
                # branch phases against round N-1's branch instead of failing.
                pending_branch = None
            else:
                if pending_branch is None or pending_branch[0] != path[0]:
                    raise SystemExit(
                        f"jsonl_to_demo_replay: a `phase_started` in {a.run} with "
                        f"`phase_path` {path} is inside a branch, but no "
                        "`conditional_evaluated` for that conditional precedes it. "
                        "`then[j]` and `else[j]` share the path, so the branch is "
                        "what disambiguates them and it cannot be guessed.")
                branch_cur = pending_branch[1]
            phase_path_cur = list(path)
        elif e == "agent_output":
            turns.append({
                "round": round_no,
                **emitted_coords(),
                "phase_type": l["phase_type"],
                "agent": l["agent"],
                "fields": ordered_fields(l["fields"]),
            })
        elif e == "shared_assignment":
            # Shared お題 for the whole round (assign target: all, #939). The
            # harness emits ONE per round, so no dedup — value only, no agent.
            value = l.get("value", "")
            code.append({
                "round": round_no,
                **emitted_coords(),
                "phase_type": phase_type_cur,
                "summary": value,
                "payload": {"kind": "sharedAssignment", "value": value},
            })
        elif e == "assignment":
            # Per-agent assignment (assign target: random_one — word wolf). Each
            # agent gets a DIFFERENT secret, so emit one line per agent (#939);
            # deduping here would collapse the wolf/villager split to one word.
            agent, value = l.get("agent", ""), l.get("value", "")
            code.append({
                "round": round_no,
                **emitted_coords(),
                "phase_type": phase_type_cur,
                "summary": f"{agent} assigned: {value}",
                "payload": {"kind": "assignment", "agent": agent, "value": value},
            })
        elif e in CODE_KIND:
            code.append({
                "round": round_no,
                **emitted_coords(),
                "phase_type": l.get("phase_type") or phase_type_cur,
                "summary": code_summary(l),
                "payload": code_payload(l),
            })

    doc = {
        "schema_version": 2,
        "preset_ref": {
            "id": preset["id"],
            "version": "1.0",
            "yaml_sha256": sha256_hex(a.preset),
        },
        "metadata": {
            "title": preset.get("name", preset["id"]),
            "description": " ".join((preset.get("description") or "").split()),
            "language": a.language or start.get("language", "ja"),
            "recorded_at": start["date"],
            "recorded_with_model": "gemma4_e2b_q4km",
            "content_filter_applied": bool(a.filter_applied),
            "total_turns": len(turns),
            "estimated_duration_ms": 15000,
            "captured_by": "tyabu12",
        },
        "turns": turns,
    }
    if code:
        doc["code_phase_events"] = code

    with open(a.out, "w", encoding="utf-8") as f:
        yaml.safe_dump(doc, f, allow_unicode=True, sort_keys=False, width=4096)
    print(f"wrote {a.out}: {len(turns)} turns, {len(code)} code-phase events")


if __name__ == "__main__":
    main()
