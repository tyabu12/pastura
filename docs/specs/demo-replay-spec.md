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

### 4.1 Layer overview

All replay components live in `App/`, co-located with
`SimulationViewModel` and `ContentFilter`. Engine/ is *not* the right
layer: replay has no inference, no scoring, no phase dispatch — it is a
UI concern that happens to reuse Models/ types (`SimulationEvent`,
`TurnOutput`, `Scenario`). Placing it in Engine/ would require Engine/
to depend on `Resources/`-bundle loading, which is an App-layer
responsibility.

The live simulation path (`Engine/SimulationRunner` → `SimulationEvent`
stream → `App/SimulationViewModel` → `Views/...`) and the replay path
(`App/BundledDemoReplaySource` → `SimulationEvent` stream →
`App/ReplayViewModel` → `Views/...`) converge at the render layer: both
feed `AgentOutputRow` and phase-header components. The VM layer is
deliberately separate because the live VM is entangled with production
persistence (§4.2).

### 4.2 `ReplayViewModel` (new, App/)

`ReplayViewModel` is a new `@Observable` `@MainActor` class under
`Pastura/Pastura/App/ReplayViewModel.swift`. It is **not** a subset or
subclass of `SimulationViewModel` — the two are siblings that share
rendering components (§4.7) but not VM logic.

Why not reuse `SimulationViewModel`:

- `SimulationViewModel.handleAgentOutput` calls `persistTurnRecord`
  (live at roughly `SimulationViewModel.swift:605-641`) which yields to
  `persistenceContinuation` writing `TurnRecord` to the production DB.
  A replayed demo running through the live VM would pollute the
  production `turns` / `simulations` tables and leak into Past Results
  Viewer as extraneous simulation entries.
- `SimulationViewModel` also owns `ContentFilter` application, thinking-
  indicator state, streaming-snapshot buffers, and engine-error
  escalation — most of which are irrelevant for replay and complicate
  reasoning about the replay state machine.

A dedicated `ReplayViewModel` is simpler to reason about, trivially
testable (no DB stubs needed), and future-proof: the live VM can evolve
its persistence contract without breaking replay.

Responsibilities of `ReplayViewModel`:

- Subscribe to `ReplaySource.events()` (an `AsyncStream<SimulationEvent>`).
- Apply `ContentFilter` at render time to every `agentOutput` /
  `summary` / `assignment` event's user-visible strings (§3.4).
- Maintain the observable view state (`currentAgentOutputs: [AgentOutputRow.State]`,
  `currentPhase: PhaseType?`, etc.) that `AgentOutputRow` and phase
  headers consume — the **same state shape** the live VM exposes, so
  view components require no branching on "live vs replay".
- Drive the playback state machine (§4.9).
- Accept an external "download complete" signal and initiate the
  transition hand-off (ADR-007 §3 owns the transition animation; this
  VM just exposes a `shouldTransition: Bool` observable).

### 4.3 `ReplaySource` protocol (new, App/)

```swift
public protocol ReplaySource: Sendable {
  /// Scenario this replay renders against; supplies persona names,
  /// phase structure, and score-display context to the view.
  var scenario: Scenario { get }

  /// Event stream yielding pre-recorded events in order, with natural
  /// pacing embedded via the delay semantics described in §3.2.
  /// The source is responsible for sleeping between events;
  /// `ReplayViewModel` multiplies delays by the playback speed before
  /// the source emits (via `ReplayPlaybackConfig`).
  func events() -> AsyncStream<SimulationEvent>
}
```

Design notes:

- The source owns *both* the scenario context and the event stream so
  a caller can swap implementations without extra coordination.
- `events()` returns a fresh stream per call — a single source can be
  played multiple times (required for loop behaviour in §4.9).
- The source does not emit `SimulationEvent.error(...)` cases;
  replay-time failures are surfaced through the VM's state machine
  rather than the event stream.

### 4.4 `BundledDemoReplaySource` (this PR)

The Phase 2 concrete `ReplaySource` implementation. Responsibilities:

- Parse a bundled YAML file (`Resources/DemoReplays/<slug>.yaml`) via
  Yams.
- Verify `preset_ref.yaml_sha256` against the currently shipped preset
  (fail to `nil` / skip if mismatch — §3.3 silent skip).
- Resolve `preset_ref.id` to a bundled `Scenario` via the existing
  `PresetLoader` / scenario repository.
- Emit `SimulationEvent`s in the order defined by the recorded `turns`
  (+ `code_phase_events` interleaved by round), with delays applied.

Design notes:

- The source holds the pre-parsed event plan (not the raw YAML) so
  `events()` can be called multiple times without re-parsing.
- YAML parsing happens at construction time; construction failures
  bubble up to the caller (typically `DemoReplayLoader`, which is the
  thing that builds a rotation of sources).

### 4.5 `UserSimulationReplaySource` (future scaffolding)

This PR does **not** implement `UserSimulationReplaySource`. The
protocol shape is committed to so that Phase 2.5+ user-replay becomes a
drop-in: construct from a `SimulationRecord.id`, read `TurnRecord`
rows via the existing repository, synthesise `SimulationEvent`s with
reasonable default delays (e.g. turn timestamps or a flat cadence).

Known future concerns to flag now (tracked in §7 Risks):

- Legacy `SimulationRecord` rows that predate a scenario-definition
  change: `UserSimulationReplaySource` must handle the case where the
  referenced scenario no longer exists or has drifted — likely by
  refusing to build the source and surfacing a user-facing "this
  simulation cannot be replayed" message.
- Delay synthesis: `SimulationRecord` does not currently store inter-
  turn timestamps. The future implementation either adds a schema
  column or applies a flat pacing heuristic.

### 4.6 `ReplayPlaybackConfig`

```swift
public struct ReplayPlaybackConfig: Sendable {
  public var speedMultiplier: Double          // delays are divided by this
  public var loopBehaviour: LoopBehaviour     // .loop / .stopAfterLast
  public var onComplete: CompletionAction     // .awaitTransitionSignal / .stopPlayback

  public enum LoopBehaviour: Sendable { case loop, stopAfterLast }
  public enum CompletionAction: Sendable {
    case awaitTransitionSignal    // used by DL-time demo — transition triggered by DL completion
    case stopPlayback             // used by future user-initiated replay
  }

  public static let demoDefault = ReplayPlaybackConfig(
    speedMultiplier: 2.0,
    loopBehaviour: .loop,
    onComplete: .awaitTransitionSignal)
}
```

The DL-time demo uses `demoDefault`. Future user-replay would use
`.stopAfterLast` + `.stopPlayback` + a user-selectable speed.

### 4.7 View integration — shared render components

`ReplayViewModel` exposes the same observable state shape as the live
`SimulationViewModel` for the slice the view layer reads:

- Per-agent rendered output rows consumed by `AgentOutputRow`.
- Current phase descriptor consumed by the phase-header view.
- Content-filtered strings only (no raw output exposed).

This means the DL-time demo screen composes existing view components
unchanged — no `if isReplay { ... } else { ... }` branches in
`AgentOutputRow`. The new view type is only the DL-time host
(`DemoReplayHostView` or similar — final name in the implementation PR)
that embeds `ReplayViewModel`-driven content alongside the DL progress
UI (ADR-007 §3).

Sharing is at the render-component level **only**, not at the VM layer.
Live VM's thinking-indicator state, streaming snapshot, error
recovery — none of those are consumed by the replay host.

### 4.8 Relationship to `ResultDetailView` (Past Results Viewer)

Past Results Viewer (#102 / #113) renders saved simulations via
`ResultDetailView` — a **static** timeline builder that loads
`TurnRecord` + `CodePhaseEventRecord` arrays on appear and renders them
as a scrollable list.

Demo replay is a **streaming** pattern: events arrive over time with
pacing, the view updates reactively. The two patterns are intentionally
different:

- Past Results: "review mode" — user wants to jump to specific turns,
  scroll freely, inspect raw JSON. Static list is the right shape.
- DL-time demo (and future user-replay, §4.5): "playback mode" — user
  wants the live-simulation feel, timed pacing, natural reveal. Event
  stream is the right shape.

Both patterns can coexist over the same saved data in the future: the
static `ResultDetailView` for inspection, the streaming
`ReplayViewModel` for playback. This spec does not design the user-
facing entry points for the future mode — that is Phase 2.5+ UX.

### 4.9 Playback state machine

The `ReplayViewModel` exposes a state machine with four observable
states:

```
.idle             ──(start)──▶   .playing(demoIndex: 0, turnCursor: 0)
.playing(i, t)    ──(turn)──▶    .playing(i, t+1)              // advance within demo
.playing(i, last) ──(next)──▶    .playing((i+1) % N, 0)        // advance to next demo
.playing(*)       ──(download complete signal)──▶ .transitioning
.transitioning    ──(done)──▶    (view removed by host)
.playing(*)       ──(foreground lost)──▶ .paused(i, t)
.paused(*)        ──(foreground regained)──▶ .playing(i, t)    // resume from position
```

Key properties:

- **Loop continues indefinitely** until the DL-complete signal arrives
  (`CompletionAction.awaitTransitionSignal`).
- **Pause on backgrounding** — when the scene phase drops below
  `.active`, the VM transitions to `.paused(i, t)` and cancels its
  outstanding sleep. On re-entering `.active`, it resumes from the
  same position (ADR-007 §3 details the iOS lifecycle interactions).
- **No user-triggered transitions** in MVP — skip/pause/seek are
  explicitly out of scope (§2 Decision 6).

The `.transitioning` state exists so ADR-007's animated hand-off to the
setup-complete screen has a named state to key view-disappear logic
against; the animation itself is owned by the DL-time host view, not
the VM.

---

## 5. Bundle Layout, Copy Slots, Multilingual, MVP Scope

*(Section stub — filled in subsequent commit.)*

---

## 6. Dev-time Log Stash

*(Section stub — filled in subsequent commit.)*

---

## 7. Risks and Consequences

*(Section stub — filled in subsequent commit.)*
