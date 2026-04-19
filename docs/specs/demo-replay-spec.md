# Spec: DL-time Demo Replay

> **Status:** Draft (companion to ADR-007 — iOS lifecycle decisions live there; this spec owns data-format and component design)
> **Date:** 2026-04-19
> **Context:** Phase 2 feature. While the Gemma 4 E2B model (~3 GB) downloads
> on first launch, the app plays back pre-recorded simulation logs so the
> user experiences Pastura's value instead of watching a progress bar.
> Recordings are curated YAML bundled with the app.

---

## Summary

Turn the model-download window into a product-demonstration window. Bundle
2–3 (minimum 3 per §5) pre-recorded simulation logs as YAML. While the
model downloads, play them back at fixed 2× speed through a dedicated
`ReplayViewModel` (NOT the production `SimulationViewModel`). Render with
the existing `AgentOutputRow` components. Loop through the set until
download completes, then transition automatically to the setup-complete
screen.

Non-goals in this PR: Swift implementation, curated recording session,
user-facing replay of their own saved simulations (scaffolded only).

---

## 1. Context

### 1.1 Problem

First-launch UX today is dominated by a ~3 GB blocking download. The
download is justified by Pastura's on-device / privacy / offline
positioning (ADR-002, ADR-003), but the user experience on launch day is
a progress bar with no indication of what the app will *do*. Two
consequences:

- **Abandonment risk during download.** Users who quit mid-download have
  invested setup time with zero value to compare against. Re-opening
  after abandoning is psychologically harder than not starting.
- **Marketing/product-demo gap.** External marketing (X, YouTube) also
  needs pre-recorded agent-simulation footage. Capturing it from a live
  device is tedious and inconsistent.

A pre-recorded demo loop solves both: it gives first-launch users a
value-preview during the wait, and produces reusable clips for external
marketing with minimal extra cost.

### 1.2 Goals

1. Reduce first-launch abandonment during model download by presenting
   live-looking agent simulations instead of a passive progress bar.
2. Give users a concrete mental model of "what Pastura does" *before*
   their first interactive simulation.
3. Maximise motivation at download-complete moment via automatic
   animated transition into the ready state.
4. Produce recordings that double as external marketing material
   (screen-capturable YAML-driven playback → consistent clips).

### 1.3 Non-goals

- **Not a replacement for the progress bar.** The progress bar (or its
  equivalent copy) still indicates download state — demo playback is
  decoration, not signalling.
- **Not a gating CTA on download completion.** Demo plays until done;
  download completion triggers a separate transition (§4).
- **Not user-replay of their own saved simulations.** The architecture
  (§4) is designed so that a future `UserSimulationReplaySource` can
  slot in, but the Phase 2 PR ships only the bundled-demo source.
- **Not a curation tool.** Recording, selection, and auditing of demo
  YAML live in a separate curator workflow (§6).

### 1.4 Why now / phase placement

Phase 2 internal, sequenced after ADR-005 submission blockers
([#148](https://github.com/tyabu12/pastura/issues/148),
[#149](https://github.com/tyabu12/pastura/issues/149)) close. **Not a
submission blocker**: the app would ship without this feature and review
would pass; this is a quality-of-first-launch improvement, not a
compliance artefact. Rationale for "Phase 2 not Phase 2.5": the feature
leverages work that is already Phase 2 complete (Past Results Viewer
[#102](https://github.com/tyabu12/pastura/issues/102) /
[#113](https://github.com/tyabu12/pastura/issues/113) established the
pattern of reading saved simulations, and existing `AgentOutputRow`
renders turns), so the incremental cost is smaller than the UX payoff.

---

## 2. Pre-decisions and Scope

The following were settled during the Issue #152 design discussion and
are recorded here as constraints, not decisions revisited in this spec.
Each references where in the spec the detailed treatment lives.

### 2.1 Decision table

| # | Decision | Detailed in |
|---|----------|-------------|
| 1 | Recording format: **YAML** (reuses Yams 6.2.1; curator-editable; JSON export deferred) | §3 |
| 2 | Recording content model: `preset_ref` (id + version + `yaml_sha256`) + recorded turns + metadata; scenario definition is **referenced**, not inlined | §3 |
| 3 | Filter timing: **filter-at-record** (curator-side) **AND filter-at-render** (ADR-005 §5.1 compliance, defense-in-depth) | §3, §4 |
| 4 | Bundle location: `Pastura/Pastura/Resources/DemoReplays/*.yaml`, total ≤ 3 MB | §5 |
| 5 | Playback speed: **fixed 2×**, no user controls (MVP) | §4 |
| 6 | Playback controls: **none** (no skip, no pause, no scrub) for MVP | §4 |
| 7 | Loop behaviour: all presets → loop from first; no termination until DL complete | §4 |
| 8 | DL-complete handling: **automatic animated transition** to setup-complete screen (not a CTA) | ADR-007 §3 |
| 9 | ViewModel architecture: **new `ReplayViewModel`** (NOT reuse of `SimulationViewModel`, which is too entangled with production DB persistence) | §4 |
| 10 | Data-source abstraction: `ReplaySource` protocol + `BundledDemoReplaySource` (this PR) + `UserSimulationReplaySource` (future, Phase 2.5+ scaffolded) | §4 |
| 11 | Render component sharing: at `AgentOutputRow`-level only (NOT at VM-level); different from `ResultDetailView` (static timeline) | §4 |
| 12 | Multilingual: **JA-only** demos for Phase 2 ship; EN localisation framework prepared via `Localizable.xcstrings` but no EN demos bundled | §5 |
| 13 | Fixed UI copy: **role-only** definition in spec; final Japanese wording decided at implementation PR copy pass | §5 |

### 2.2 Scope framing

This spec and the companion ADR-007 bind **design-time** decisions. The
Swift implementation (`ReplayViewModel`, `BundledDemoReplaySource`,
`ReplayPlaybackConfig`, view wiring), the curator workflow (actual YAML
recordings), and the CI drift-guard script (§3.3) are tracked in
separate sub-issues and ship in separate PRs. This PR is docs-only.

---

## 3. Data Format (YAML Schema)

### 3.1 Shape

A single demo replay is one YAML document at
`Pastura/Pastura/Resources/DemoReplays/<slug>.yaml`. Three top-level
sections:

- `preset_ref` — which shipped scenario preset this recording targets,
  plus a hash-based drift guard (§3.3).
- `metadata` — display / audit fields used by curator and optional
  future viewer UI.
- `turns` — the pre-recorded event sequence, one entry per rendered
  LLM output (or code-phase event).

Scenario definition (personas, phases, score rules) is *not* inlined.
At load time the replay locates its `preset_ref.id` in the already-
bundled presets and uses that scenario as the render context.

### 3.2 Full schema (v1)

```yaml
schema_version: 1

preset_ref:
  id: word_wolf              # must match a shipped preset id (Resources/Presets/*.yaml or DB isPreset=true)
  version: "1.0"             # informational; surface mismatches in CI, not at runtime
  yaml_sha256: 9f…           # REQUIRED — SHA-256 of the preset YAML as shipped at record time

metadata:
  title: Word Wolf — spot the imposter
  description: Four agents vote on who holds the different word.
  language: ja               # ISO 639-1; Phase 2 ship is ja-only
  recorded_at: 2026-04-15T12:00:00Z
  recorded_with_model: gemma4_e2b_q4km
  content_filter_applied: true   # §3.4 — curator asserts record-time ContentFilter coverage
  total_turns: 12
  estimated_duration_ms: 90000   # at the speed captured; playback multiplier is independent
  captured_by: tyabu12           # pseudonymous identifier; §6 stash flow

turns:
  - round: 1
    phase_index: 0               # indexes into preset.phases at load time
    phase_type: speak_all        # denormalised for cheap consistency check
    agent: Alice                 # must exist in preset.personas
    fields:                      # matches TurnOutput.fields shape
      statement: "I think the word might be 'cat'."
      inner_thought: "The others seem confident."
    delay_ms_before: 1200        # natural inter-turn pace; playback speed multiplies this
  - round: 1
    phase_index: 0
    phase_type: speak_all
    agent: Bob
    fields:
      statement: "…"
    delay_ms_before: 800
  # …

code_phase_events:               # optional; present if the preset has score_calc / scenario-gen phases
  - round: 2
    phase_index: 3
    phase_type: score_calc
    summary: "Scores updated: Alice +1, Bob +1"
    delay_ms_before: 500
```

Notes on field choices:

- **`phase_index` + `phase_type` together.** Index is the source of truth
  for rendering; `phase_type` is a denormalised safety check caught by
  the CI guard (§3.3) to detect preset drift that reorders phases without
  changing sha.
- **`fields` dict, not typed accessors.** Mirrors `TurnOutput.fields:
  [String: String]` so the replay can construct a `TurnOutput` without
  a separate schema layer.
- **`delay_ms_before` on every entry.** Playback multiplier (§4) scales
  all delays uniformly; natural pacing is preserved.
- **`code_phase_events` separate from `turns`.** Matches Past Results
  Viewer's separation between agent output and code-phase events
  (established in #102 / #113).

### 3.3 Preset drift detection and CI guard

The `preset_ref.yaml_sha256` field is load-bearing. At build time:

- A CI script (ships in the Swift implementation PR, not this docs PR)
  computes SHA-256 of every shipped preset YAML and every bundled demo
  YAML's `preset_ref.yaml_sha256`. Any bundled demo whose
  `preset_ref.yaml_sha256` does not match any shipped preset **fails the
  build**.
- At runtime, the replay loader re-verifies the hash before presenting
  the demo. A mismatch causes a **silent skip** to the next demo in the
  loop (§4), with a diagnostic logged via the existing logging pipeline.

Silent skip is the intended runtime posture — the DL demo surface is
ambient; a loud error would be worse than a shorter rotation. The CI
guard is the tight-loop catch that prevents drift from shipping at all.

If a preset changes intentionally (new prompt wording, added phase,
renamed persona), the curator re-records affected demos and re-computes
hashes before the PR containing the preset change merges. §5 sets a
minimum playable count so drift during a preset change cannot leave
zero playable demos.

### 3.4 Filter policy: at-record AND at-render

`ContentFilter` is applied on **both sides** of the recording boundary:

- **At record time** (curator workflow, §6): the curator reviews recorded
  YAML and runs the current blocklist against every `fields.*` string
  and `code_phase_events[].summary`. The `metadata.content_filter_applied:
  true` flag is set only after manual audit.
- **At render time** (ADR-005 §5.1 compliance): `ReplayViewModel`
  invokes `ContentFilter.filter(_:)` on every rendered field, just like
  the live simulation path. The filter is `nonisolated + Sendable` and
  idempotent, so the double application is a no-op on already-filtered
  content but enforces ADR-005 §5.1's "every user-visible display
  surface MUST pass through `ContentFilter`" invariant without
  exemption carve-outs.

Why both? Record-time filtering is curation hygiene — the audit point
where a human decides whether a recording is appropriate before bundling.
Render-time filtering is *the* compliance checkpoint. Skipping one of
the two degrades either curation quality or policy compliance; the cost
of running both is effectively zero.

ADR-007 §4 restates this boundary for the lifecycle reader; this spec
owns the policy-implementation side.

### 3.5 Schema evolution

`schema_version: 1` is the current shape. Future changes:

- **v2 additive** (e.g. inline `scenario_def` fallback for self-
  contained demos, or audio annotation tracks): bump to `2`, loader
  supports both, older demos keep working.
- **v2 breaking** (e.g. change `turns` from array-of-entries to
  per-phase grouping): version bump and loader fork; deprecate v1 only
  after all bundled demos re-recorded.

The loader rejects unknown `schema_version` values with a silent skip
(matching §3.3's posture) rather than a fatal load — unknown version
is treated as a kind of drift.

---

## 4. Replay Architecture

*(Section stub — filled in subsequent commit.)*

---

## 5. Bundle Layout, Copy Slots, Multilingual, MVP Scope

*(Section stub — filled in subsequent commit.)*

---

## 6. Dev-time Log Stash

*(Section stub — filled in subsequent commit.)*

---

## 7. Risks and Consequences

*(Section stub — filled in subsequent commit.)*
