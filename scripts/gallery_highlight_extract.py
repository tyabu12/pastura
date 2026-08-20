#!/usr/bin/env python3
"""Convert a pastura-harness JSONL transcript + a curated selection into
`docs/gallery/highlights/<id>.json` (ADR-029 Decision 1's schema).

**Curation is human judgment; extraction is mechanical.** This tool never
chooses excerpts — you pass explicit line numbers from the transcript and it
slices, validates, pins hashes, and audits. Spoiler and quality judgment are
taste calls the blocklist audit cannot make (the audit is necessary, not
sufficient), and each batch still needs a human sign-off before commit.

Selection: `--pick <line>` (repeatable, 1-based line number in the JSONL —
each must be an `agent_output` line) or a `--selection <file.json>`:

    {
      "picks": [12, {"line": 15, "source_field": "statement"}],
      // kind: "persona" (the fragment is a persona list — the app draws it in
      // the visual editor's vocabulary) or "raw" (published as a YAML block).
      // Required, no default; a persona fragment's shape is gate-checked.
      "yaml_hook": {"kind": "raw",
                    "fragment": "phases:\\n  - type: speak_each", "caption": "…"},
      "teaser": "…",
      // optional. Omitted, `run_start.model` is resolved to a `ModelRegistry`
      // id — the harness writes a *display name* there, and the slug is what
      // ships. Supply one only to override; a value that is neither an id nor a
      // known displayName hard-fails either way.
      "model": "gemma-4-e2b-q4-k-m",
      "generated_at": "2026-08-05"         // optional; default today (UTC)
    }

CLI flags override the selection file.

Usage:
  gallery_highlight_extract.py --run <run.jsonl> --id <gallery_id> \\
      --selection <selection.json> [--window-override] [--out <path>]

Hard-fails (each with a distinct, greppable message):
  - the scenario YAML declares the `secret:` mechanism (ADR-029 Decision 2 —
    the spoiler rules are unvalidated for it);
  - a scenario whose `phases:` tree cannot be flattened — a `conditional`
    with neither branch, or one nested inside a branch (both refused by
    `ScenarioValidator` too);
  - a `phase_started` line carrying no usable `phase_path`, one deeper than
    the engine's depth-1 rule allows, or one naming a phase / branch position
    the pinned YAML does not have;
  - a branch `phase_path` with no preceding `conditional_evaluated` to say
    which branch was taken (`then[j]` and `else[j]` share the path);
  - a transcript phase name outside the `PhaseType` catalog (a new phase type
    landed; classify it in ADR-029 Decision 3 first);
  - a pick that is not an `agent_output` line, or whose phase / source_field /
    position / round violates Decision 3;
  - a pick whose `agent` is absent from the scenario's `personas:` list, or a
    YAML with no readable `personas:` — every excerpt entry pins the speaker's
    index into that list as `persona_index`, derived here and never selectable;
  - more than 8 excerpt entries; a blocklist match; a stale `yaml_sha256`.

The gate (`scripts/check-gallery-entry.sh`), not this tool, is the enforcement
point — a hand-edited highlight never runs this. The checks here are fail-fast
convenience and share their implementation with the gate
(`scripts/gallery_highlight_validate.py`).
"""
import argparse
import collections
import datetime
import json
import os
import sys

import yaml  # PyYAML — reads the gallery scenario YAML to detect `secret:`

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gallery_highlight_validate as ghv  # noqa: E402

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def die(message):
    raise SystemExit(f"gallery_highlight_extract: {message}")


def declares_secret(node):
    """True if a `secret:` key appears anywhere in the parsed scenario."""
    if isinstance(node, dict):
        if "secret" in node:
            return True
        return any(declares_secret(v) for v in node.values())
    if isinstance(node, list):
        return any(declares_secret(v) for v in node)
    return False


def read_transcript(path):
    """-> (lines_by_number, run_start). Each entry is (lineno, parsed dict)."""
    lines, run_start = {}, None
    with open(path, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, 1):
            if not raw.strip():
                continue
            try:
                obj = json.loads(raw)
            except ValueError as exc:
                die(f"malformed JSONL at {path}:{lineno}: {exc}")
            lines[lineno] = obj
            if obj.get("type") == "run_start":
                run_start = obj
    if run_start is None:
        die(f"no run_start line in {path} — is this a pastura-harness transcript?")
    return lines, run_start


def annotate(lines, nodes):
    """Carry `round` and `phase_index` forward onto every event line.

    `agent_output` lines carry no `round` (ADR-029 Decision 2's mechanical
    note) — it comes from the preceding `round_started`.

    `phase_index` indexes the entry's flattened `phases`, while a transcript's
    `phase_path` is a TREE path (`[i]`, or `[i, j]` inside a branch). Those
    coincide only for a scenario with no `conditional`, so the path is resolved
    against `nodes` — `flatten_phase_tree`'s node list, in the same order
    `gallery.json` stores.

    `[i, j]` alone does not say WHICH branch: `then[j]` and `else[j]` carry the
    identical path. The branch comes from the `conditional_evaluated` the
    harness emits between the conditional's own `phase_started` and its
    branch's (`ConditionalHandler.execute` evaluates, then runs the branch).
    That event carries no `phase_path` of its own, so it is attributed to the
    most recent `phase_started` whose type is `conditional` — sound because the
    engine's depth-1 rule means at most one conditional is ever in flight.

    Every failure here is fatal rather than a fallback: an invented coordinate
    reads as measured fact to every downstream check.
    """
    by_top = {}
    by_branch = {}
    for flat_idx, node in enumerate(nodes):
        if node.branch is None:
            by_top[node.top] = flat_idx
        else:
            by_branch[(node.top, node.branch, node.inner)] = flat_idx
    branch_len = collections.Counter(
        (n.top, n.branch) for n in nodes if n.branch is not None)

    context, round_no, phase_idx = {}, None, None
    pending_branch = None   # (top, "then"/"else") from the last conditional_evaluated
    open_conditional = None  # top-level index of the conditional currently in flight
    for lineno in sorted(lines):
        obj = lines[lineno]
        if obj.get("type") != "event":
            continue
        event = obj.get("event")
        if event == "round_started":
            round_no = obj.get("round")
        elif event == "conditional_evaluated":
            if open_conditional is None:
                die(f"line {lineno} — `conditional_evaluated` with no preceding "
                    "`phase_started` of type `conditional`, so the branch it "
                    "decides cannot be attributed to a phase")
            result = obj.get("result")
            if not isinstance(result, bool):
                die(f"line {lineno} — `conditional_evaluated.result` is "
                    f"{result!r}, not a boolean; the taken branch cannot be "
                    "derived from it")
            pending_branch = (open_conditional, "then" if result else "else")
        elif event == "phase_started":
            path = obj.get("phase_path")
            # Refuse rather than default to 0. The harness always writes this
            # field, so a missing one means the log is not what it claims — and
            # a fallback would assert "top-level phase 0" on the excerpt's
            # behalf, which every downstream check then reads as measured fact.
            if not isinstance(path, list) or not path:
                die(f"line {lineno} — `phase_started` carries no usable "
                    "`phase_path`, so phase_index cannot be derived for any pick "
                    "in this phase")
            if len(path) > 2:
                die(f"line {lineno} — `phase_path` {path} is {len(path)} deep, but "
                    "the engine's depth-1 rule bounds it to 2 (ScenarioValidator "
                    "blocks a nested `conditional` at load; ConditionalHandler "
                    "registers no sub-handler for one at run time). A deeper path "
                    "means the transcript and that rule disagree — resolving it "
                    "would need a branch decision this tool cannot make.")
            if len(path) == 1:
                if path[0] not in by_top:
                    die(f"line {lineno} — `phase_path` {path} names top-level phase "
                        f"{path[0]}, which the scenario's `phases:` does not have "
                        f"(it has {len(by_top)}). The transcript and the pinned "
                        "YAML disagree — check that the run used this exact "
                        "scenario file.")
                phase_idx = by_top[path[0]]
                open_conditional = (
                    path[0] if nodes[phase_idx].type == "conditional" else None)
                # Cleared on EVERY top-level phase, conditional included: the
                # engine re-evaluates the condition once per round, so carrying
                # the previous round's verdict forward would resolve round N's
                # branch phases against round N-1's branch instead of failing.
                pending_branch = None
            else:
                top, inner = path[0], path[1]
                if pending_branch is None or pending_branch[0] != top:
                    die(f"line {lineno} — `phase_path` {path} is inside a branch, but "
                        "no `conditional_evaluated` for that conditional precedes "
                        "it. `then[j]` and `else[j]` share the path, so the branch "
                        "is what disambiguates them and it cannot be guessed.")
                branch = pending_branch[1]
                key = (top, branch, inner)
                if key not in by_branch:
                    die(f"line {lineno} — `phase_path` {path} names position {inner} "
                        f"of the `{branch}` branch at top-level phase {top}, which "
                        f"has {branch_len[(top, branch)]} phase(s). The transcript "
                        "and the pinned YAML disagree — check that the run used "
                        "this exact scenario file.")
                phase_idx = by_branch[key]
        context[lineno] = (round_no, phase_idx)
    return context


def check_phase_catalog(lines, run_path):
    """Hard-fail on any phase name outside the PhaseType catalog."""
    unknown = set()
    for obj in lines.values():
        if obj.get("type") != "event":
            continue
        phase = obj.get("phase_type")
        if phase is not None and phase not in ghv.PHASE_TYPES:
            unknown.add(phase)
    if unknown:
        die(
            f"unknown phase — {sorted(unknown)} in {run_path} is outside the "
            "PhaseType catalog this tool last synced with. A new phase type "
            "landed (ADR-022 extension contract): assign its visibility and "
            "outcome classification in ADR-029 Decision 3, update "
            "gallery_highlight_validate.PHASE_TYPES, then re-run.")


def normalize_picks(raw_picks):
    """-> [(lineno, source_field)] from ints and/or {line, source_field} objects."""
    picks = []
    for item in raw_picks:
        if isinstance(item, bool):
            die(f"invalid pick {item!r} — expected a line number or object")
        if isinstance(item, int):
            picks.append((item, "statement"))
        elif isinstance(item, dict) and isinstance(item.get("line"), int):
            picks.append((item["line"], item.get("source_field", "statement")))
        else:
            die(f"invalid pick {item!r} — expected a line number or "
                "{\"line\": N, \"source_field\": \"statement\"}")
    return picks


def build_excerpt(picks, lines, context, run_path, persona_names):
    # A retried harness run appends attempt 2 to the same JSONL and round
    # numbering restarts at 1, so a pick landing in the discarded attempt
    # would be silently mis-contextualized (its round derived from the dead
    # attempt while source.run_id implies the completed one). Only the final
    # attempt is pickable; the validator never sees the transcript, so this
    # is the sole enforcement point.
    max_attempt = max(
        (o.get("attempt") or 1) for o in lines.values() if o.get("type") == "event")
    excerpt = []
    for lineno, source_field in picks:
        obj = lines.get(lineno)
        if obj is None:
            die(f"pick {lineno} — no such (non-blank) line in {run_path}")
        if (obj.get("attempt") or 1) != max_attempt:
            die(f"pick {lineno} — belongs to attempt {obj.get('attempt')}, but the "
                f"log's final attempt is {max_attempt}; a retried run renumbers "
                "rounds, so picks must come from the final attempt only")
        if obj.get("type") != "event" or obj.get("event") != "agent_output":
            die(f"pick {lineno} — line is {obj.get('event') or obj.get('type')!r}, "
                "not an `agent_output` event; only a persona utterance is "
                "excerpt-eligible (ADR-029 Decision 3)")
        round_no, phase_idx = context.get(lineno, (None, None))
        if round_no is None:
            die(f"pick {lineno} — no preceding `round_started` line, so the round "
                "cannot be derived")
        if phase_idx is None:
            die(f"pick {lineno} — no preceding `phase_started` line, so phase_index "
                "cannot be derived")
        fields = obj.get("fields") or {}
        if source_field not in fields:
            die(f"pick {lineno} — the agent_output carries no {source_field!r} field "
                f"(has {sorted(fields)})")
        agent = obj.get("agent", "")
        # Hard-fail rather than omit the key or write a sentinel: a speaker the
        # scenario does not declare means the transcript and the pinned YAML
        # disagree, so the index the consumers colour from would be arbitrary.
        if agent not in persona_names:
            die(f"pick {lineno} — agent {agent!r} is not in the scenario's "
                f"`personas:` list {persona_names}; persona_index cannot be "
                "derived. The transcript and the pinned YAML disagree — check "
                "that the run used this exact scenario file.")
        excerpt.append({
            "agent": agent,
            "round": round_no,
            "phase": obj.get("phase_type", ""),
            "phase_index": phase_idx,
            "persona_index": persona_names.index(agent),
            "source_field": source_field,
            "text": fields[source_field],
        })
    return excerpt


def resolve_model_id(raw, allowed_model_ids, display_to_id):
    """-> a `ModelRegistry` id for `raw`, or die.

    The harness writes `ModelProfile.name` — a **display name** like
    `Gemma 4 E2B (Q4_K_M)` — into `run_start.model`, while every shipped
    highlight and the landing pages want the slug (`gemma-4-e2b-q4-k-m`). An
    unresolved one would reach `source.model` and publish verbatim in
    user-facing prose, showing one model under two names.
    """
    if not isinstance(raw, str):
        die(f"model must be a string, got {type(raw).__name__} ({raw!r}) — check "
            "the selection file's `model` value")
    if not raw:
        die("no model — the transcript's run_start carries none and neither "
            "--model nor the selection file supplied one")
    if raw in allowed_model_ids:
        return raw
    mapped = display_to_id.get(raw)
    if mapped is not None:
        return mapped
    die(f"unknown model {raw!r} — it is neither a ModelRegistry id "
        f"{sorted(allowed_model_ids)} nor a known displayName "
        f"{sorted(display_to_id)}. Pass --model with the registry id the run "
        "actually used.")


def load_selection(args):
    sel = {}
    if args.selection:
        with open(args.selection, encoding="utf-8") as f:
            sel = json.load(f)
        if not isinstance(sel, dict):
            die(f"{args.selection} must contain a JSON object")
    picks = list(args.pick) if args.pick else list(sel.get("picks") or [])
    if not picks:
        die("no picks — pass --pick <line> (repeatable) or a --selection file "
            "with a non-empty `picks` array. This tool never chooses excerpts.")
    hook = sel.get("yaml_hook") or {}
    fragment = args.yaml_hook_fragment or hook.get("fragment")
    caption = args.yaml_hook_caption or hook.get("caption")
    # No default. `persona` licenses the app's editor-vocabulary rendition and
    # `raw` publishes the fragment as YAML, so guessing either would make a
    # presentation decision on the curator's behalf (ADR-029 § Amendment
    # 2026-08-08). The gate re-derives the shape `persona` promises.
    kind = args.yaml_hook_kind or hook.get("kind")
    teaser = args.teaser or sel.get("teaser")
    for name, value in (("yaml_hook.kind", kind), ("yaml_hook.fragment", fragment),
                        ("yaml_hook.caption", caption), ("teaser", teaser)):
        if not value:
            die(f"missing {name} — supply it via --selection or the matching CLI flag")
    if kind not in ghv.YAML_HOOK_KINDS:
        die(f"yaml_hook.kind={kind!r} is not in the allowlist "
            f"{sorted(ghv.YAML_HOOK_KINDS)} (ADR-029 Decision 1)")
    return {
        "picks": normalize_picks(picks),
        "kind": kind,
        "fragment": fragment,
        "caption": caption,
        "teaser": teaser,
        "model": args.model or sel.get("model"),
        "generated_at": args.generated_at or sel.get("generated_at"),
    }


def main():
    ap = argparse.ArgumentParser(description="Extract a gallery highlight (ADR-029).")
    ap.add_argument("--run", required=True, help="pastura-harness run JSONL")
    ap.add_argument("--id", required=True, help="gallery.json scenario id")
    ap.add_argument("--selection", help="JSON selection file (see module docstring)")
    ap.add_argument("--pick", type=int, action="append",
                    help="1-based JSONL line number of an agent_output to excerpt")
    ap.add_argument("--yaml-hook-kind",
                    help="persona | raw — how a consumer may render the fragment "
                         "(ADR-029 Decision 1). Required; there is no default.")
    ap.add_argument("--yaml-hook-fragment")
    ap.add_argument("--yaml-hook-caption")
    ap.add_argument("--teaser")
    ap.add_argument("--model")
    ap.add_argument("--generated-at")
    ap.add_argument("--window-override", action="store_true",
                    help="accept excerpts past the default round window; recorded "
                         "in the output as window_override: true")
    ap.add_argument("--gallery-dir", default=os.path.join(REPO_ROOT, "docs", "gallery"))
    ap.add_argument("--blocklist", default=os.path.join(
        REPO_ROOT, "Pastura", "Pastura", "Resources", "ContentBlocklist.json"))
    ap.add_argument("--model-registry", default=os.path.join(
        REPO_ROOT, "Pastura", "Pastura", "App", "ModelRegistry.swift"))
    ap.add_argument("--out", help="output path (default <gallery-dir>/highlights/<id>.json)")
    args = ap.parse_args()

    gallery_json = os.path.join(args.gallery_dir, "gallery.json")
    with open(gallery_json, encoding="utf-8") as f:
        entries = json.load(f).get("scenarios") or []
    entry = next((e for e in entries if e.get("id") == args.id), None)
    if entry is None:
        die(f"no gallery.json entry with id={args.id} ({gallery_json})")

    yaml_path = os.path.join(args.gallery_dir, os.path.basename(entry.get("yaml_url", "")))
    if not os.path.isfile(yaml_path):
        die(f"sibling YAML not found: {yaml_path}")
    scenario = yaml.safe_load(open(yaml_path, encoding="utf-8"))
    if declares_secret(scenario):
        die(f"secret mechanism — {yaml_path} declares `secret:` persona fields. "
            "ADR-029 Decision 2 refuses this branch: the spoiler rules are "
            "unvalidated for it, so extraction would risk shipping a spoiler. "
            "Design and test the secret branch first, then lift this refusal.")

    yaml_sha = ghv.sha256_file(yaml_path)
    if yaml_sha != entry.get("yaml_sha256"):
        die(f"yaml_sha256 mismatch — {yaml_path} hashes to {yaml_sha} but "
            f"gallery.json has {entry.get('yaml_sha256')}. The index is stale or "
            "points at the wrong file; fix it before pinning a highlight to it.")

    persona_names = ghv.scenario_persona_names(scenario)
    if persona_names is None:
        die(f"unreadable personas — {yaml_path} has no `personas:` list of "
            "mappings each carrying a string `name`. Every excerpt entry pins "
            "the speaker's index into that list (ADR-029 Decision 1), so it "
            "cannot be derived.")

    nodes, tree_reason = ghv.flatten_phase_tree(scenario)
    if nodes is None:
        die(f"unreadable phases — {tree_reason}. Every excerpt entry pins a "
            "`phase_index` into the flattened phase list, so it cannot be "
            "derived.")

    lines, run_start = read_transcript(args.run)
    check_phase_catalog(lines, args.run)
    context = annotate(lines, nodes)
    selection = load_selection(args)
    excerpt = build_excerpt(
        selection["picks"], lines, context, args.run, persona_names)

    registry = ghv.registry_model_ids(args.model_registry)
    if registry is None:
        die(f"model registry — no ModelDescriptor id readable from "
            f"{args.model_registry}; source.model cannot be resolved or checked.")
    registry_ids, display_to_id = registry
    allowed_model_ids = registry_ids | ghv.RETIRED_MODEL_IDS
    model = resolve_model_id(
        selection["model"] or run_start.get("model", ""),
        allowed_model_ids, display_to_id)

    doc = {
        "schema_version": ghv.SCHEMA_VERSION,
        "scenario_ref": {"id": args.id, "yaml_sha256": yaml_sha},
        "source": {
            "model": model,
            "run_id": run_start.get("run_id", ""),
            "generated_at": selection["generated_at"]
            or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
        },
        "excerpt": excerpt,
        "yaml_hook": {
            "kind": selection["kind"],
            "fragment": selection["fragment"],
            "caption": selection["caption"],
        },
        "teaser": selection["teaser"],
        "window_override": bool(args.window_override),
        "content_filter_applied": True,
    }

    if not os.path.isfile(args.blocklist):
        die(f"ContentBlocklist.json not found at {args.blocklist} — the "
            "publish-time audit is mandatory (ADR-029 Decision 2)")
    blocklist = ghv.load_blocklist(args.blocklist)
    failures = ghv.check_content(
        doc, entry, blocklist, f"[{args.id}]",
        personas=(persona_names, None), allowed_model_ids=allowed_model_ids,
        phase_tree=ghv.flatten_phase_tree(scenario))
    if failures:
        for line in failures:
            print(line, file=sys.stderr)
        die(f"{len(failures)} validation failure(s) — nothing written")

    out_path = args.out or os.path.join(args.gallery_dir, "highlights", f"{args.id}.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    # Fixed key order (insertion order above), UTF-8, trailing newline — the
    # file's raw bytes are hashed into gallery.json, so output must be
    # byte-deterministic across runs.
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {out_path}: {len(excerpt)} excerpt entries")
    print(f"highlight_sha256: {ghv.sha256_file(out_path)}")
    print("Next: add highlight_url + highlight_sha256 to the gallery.json entry "
          "(both or neither), then run scripts/check-gallery-entry.sh --all.")


if __name__ == "__main__":
    main()
