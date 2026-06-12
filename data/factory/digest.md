# Scenario Factory Digest

Committed output of the `/scenario-factory` skill (ADR-013 Phase 2,
#521): one section per cycle date, newest first, written by
`.claude/skills/scenario-factory/scripts/append_digest.py` — not by
hand. Raw run logs and generated YAMLs stay local-only (gitignored
`data/factory/runs/` and `data/factory/scenarios/`).

Judge scores cover quality (coherence / interaction / breakdown-free /
humor) only — they are NOT a content-safety screen; safety is enforced
by the blocklist pre-commit gate at promotion time.

<!-- factory-digest:sections -->

<!-- factory-digest:promotion -->
Promotion: copy the winning YAML from `data/factory/scenarios/<date>/` to `Pastura/Pastura/Resources/Presets/` via an `/orchestrate` PR — landing under `Resources/` routes it through the blocklist pre-commit gate.
