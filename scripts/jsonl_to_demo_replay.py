#!/usr/bin/env python3
"""Convert a pastura-harness run JSONL into a DL-time demo-replay YAML.

This is the curator tool behind the "exporter-captured demos" long-term
plan (demo-replay-spec.md §6): instead of hand-authoring demo YAMLs, run a
scenario through `pastura-harness` (ADR-013, real local Gemma inference),
pick the best transcript, and convert it here.

Output schema: demo-replay-spec.md §3.2 (schema_version=1, preset_ref,
metadata, turns, code_phase_events). Field selection mirrors
`Pastura/Pastura/App/YAMLReplayExporter.swift`; payload `kind`
discriminators match `YAMLReplaySource.decodePayloadStanza`.

Mapping:
  - `agent_output`  -> `turns[]`            (statement/inner_thought or vote/reason)
  - `assignment`    -> one `assignment` code-phase event per round (scene-setter;
                       deduped — every agent gets the same topic, so only the
                       first is emitted to set the scene without N identical rows)
  - `vote_results`  -> `voteResults`
  - `score_update`  -> `scoreUpdate`
  - `elimination`   -> `elimination`
  - `summary`       -> `summary`
  - `event_injected`-> `eventInjected`
  - `pairing_result`-> `pairingResult`
`phase_index` is taken from the most recent `phase_started.phase_path[0]`
(these scenarios have flat phase lists, so the first path element is the
phase index the demo schema expects).

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

# Stable field order for turn `fields` (mirrors existing hand-authored demos:
# statement before inner_thought, vote before reason). Unknown keys keep
# their source order after these.
FIELD_ORDER = ["statement", "inner_thought", "action", "vote", "reason"]


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
        return {"kind": kind}
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
    round_no, phase_idx, phase_type_cur = 0, 0, ""
    scene_set_rounds = set()  # rounds whose assignment scene-setter is already emitted
    for l in lines:
        if l.get("type") != "event":
            continue
        e = l.get("event")
        if e == "round_started":
            round_no = l["round"]
        elif e == "phase_started":
            # Track both the index and the phase_type of the current phase.
            # Code-phase events (vote_results / score_update / summary /
            # event_injected) carry NO phase_type of their own, so the demo's
            # phase_type — which must equal scenario.phases[phase_index].type
            # (BundledDemoReplaySource rejects the demo otherwise) — has to
            # come from the enclosing phase_started, not the event name.
            phase_idx = (l.get("phase_path") or [0])[0]
            phase_type_cur = l.get("phase_type", "")
        elif e == "agent_output":
            turns.append({
                "round": round_no,
                "phase_index": phase_idx,
                "phase_type": l["phase_type"],
                "agent": l["agent"],
                "fields": ordered_fields(l["fields"]),
            })
        elif e == "assignment":
            # Scene-setter: every agent gets the same topic, so emit only the
            # first assignment of each round to set the scene (the topic/お題).
            if round_no in scene_set_rounds:
                continue
            scene_set_rounds.add(round_no)
            agent, value = l.get("agent", ""), l.get("value", "")
            code.append({
                "round": round_no,
                "phase_index": phase_idx,
                "phase_type": phase_type_cur,
                "summary": f"{agent} assigned: {value}",
                "payload": {"kind": "assignment", "agent": agent, "value": value},
            })
        elif e in CODE_KIND:
            code.append({
                "round": round_no,
                "phase_index": phase_idx,
                "phase_type": l.get("phase_type") or phase_type_cur,
                "summary": code_summary(l),
                "payload": code_payload(l),
            })

    doc = {
        "schema_version": 1,
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
