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
  - a transcript phase name outside the `PhaseType` catalog (a new phase type
    landed; classify it in ADR-029 Decision 3 first);
  - a pick that is not an `agent_output` line, or whose phase / source_field /
    position / round violates Decision 3;
  - a pick whose `agent` is absent from the scenario's `personas:` list, or a
    YAML with no readable `personas:` — every excerpt entry pins the speaker's
    index into that list as `persona_index`, and it is derived here, never
    selectable (it is what the app and the web resolve the avatar colour slot
    from, so a wrong one silently recolours the excerpt);
  - more than 8 excerpt entries; a blocklist match; a stale `yaml_sha256`.

The gate (`scripts/check-gallery-entry.sh`), not this tool, is the enforcement
point — a hand-edited highlight never runs this. The checks here are fail-fast
convenience and share their implementation with the gate
(`scripts/gallery_highlight_validate.py`).
"""
import argparse
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


def annotate(lines):
    """Carry `round` and `phase_index` forward onto every event line.

    `agent_output` lines carry no `round` (ADR-029 Decision 2's mechanical
    note) — it comes from the preceding `round_started`. `phase_index` comes
    from the enclosing `phase_started.phase_path[0]`; gallery scenarios have
    flat phase lists, so the first path element is the index into `phases`.
    """
    context, round_no, phase_idx = {}, None, None
    for lineno in sorted(lines):
        obj = lines[lineno]
        if obj.get("type") != "event":
            continue
        event = obj.get("event")
        if event == "round_started":
            round_no = obj.get("round")
        elif event == "phase_started":
            phase_idx = (obj.get("phase_path") or [0])[0]
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
        # disagree, and the avatar colour the consumers resolve from this index
        # would be arbitrary. Silently skipping would leave the gate's
        # cross-check with nothing to compare (ADR-029 Decision 1).
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
    highlight and the landing pages want the slug (`gemma-4-e2b-q4-k-m`). So the
    default path resolves the display name rather than passing it through: an
    unresolved one would reach `source.model`, publish verbatim in user-facing
    prose, and show the same model under two names on neighbouring pages.
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

    lines, run_start = read_transcript(args.run)
    check_phase_catalog(lines, args.run)
    context = annotate(lines)
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
        personas=(persona_names, None), allowed_model_ids=allowed_model_ids)
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
