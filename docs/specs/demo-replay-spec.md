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

**Persistence absence is enforced by construction, not by convention.**
`ReplayViewModel`'s initialiser takes no repository, no database writer,
no `EventStore`-style sink — it has no dependency capable of writing
to the production DB. Demo replay cannot accidentally pollute
`turns` / `simulations` tables because the wiring to write them simply
does not exist on the replay path. Any future addition of a persistence
argument to `ReplayViewModel` would require revisiting this spec.

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

### 5.1 Bundle layout

Demo recordings ship bundled with the app under:

```
Pastura/Pastura/Resources/DemoReplays/
  <slug>.yaml          # one file per demo
```

Slugs are kebab-case and match their `metadata.title` only loosely —
the filename is the stable identifier, `title` is display-only. Target
3–5 files bundled initially. A manifest is *not* required: the app
enumerates `*.yaml` under `DemoReplays/` at launch and validates each
against the schema.

### 5.2 MVP scope floors

To prevent scope drift at curation time, the spec pins the following
numeric floors. Implementation PR CI (the drift-guard script, §3.3) also
checks these.

| Constraint | Floor | Ceiling | Rationale |
|------------|-------|---------|-----------|
| Number of demos bundled | **≥ 3** | — | Loop behaviour (§4) needs variety; fewer than 3 risks feeling repetitive within a single DL window |
| Turns per demo | **≥ 6** | — | A single-exchange recording does not read as "a simulation unfolding" — users need to see an arc |
| Per-demo YAML size | — | **≤ 1 MB** | One bloated demo should not crowd out others |
| Total `DemoReplays/` size | — | **≤ 3 MB** | Phase 2 bundle-size discipline; the user's original estimate |
| Minimum *playable* demos at runtime | **≥ 2** | — | After sha-drift silent-skip (§3.3), the playlist must still have ≥ 2 entries — otherwise fall back to a progress-bar-only DL screen (§5.3) |

If the minimum-playable floor is violated at runtime (all but one demo
skipped due to drift), the DL host view rolls back to the non-demo
progress-bar UX rather than loop a single demo on repeat. This is the
failsafe for schema drift detected only after ship.

### 5.3 Fallback when no demos are playable

If zero demos pass validation at launch, the DL-time host shows the
classic progress-bar-only layout (essentially the current
`ModelDownloadView`). No user-facing error is shown — the demo feature
is ambient enhancement, not a required UX element.

The implementation PR's validation pipeline logs the skip reason via
the existing logging pipeline so the curator/maintainer can notice
drift even when no user reports it.

### 5.4 Static UI copy slots

The DL-time demo host screen has **three fixed copy slots** surrounding
the replay area. This spec defines the **roles**; final wording is
decided at the implementation-PR copy pass (see §2 decision 13).

| Slot | Role | Working draft (JA) | Notes |
|------|------|---------------------|-------|
| A. Intro | Single-line framing for what the user is watching | `「AIエージェントが、あなたのiPhoneの中で対話します」` | Tone: product vision in one line |
| B. Wait | Context for why user is waiting + soften the implied "please watch" | `「少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ」` | Tone: acknowledges wait, invites rather than demands |
| C. Value | Key differentiators (privacy/offline/cost) | `「広告なし、無料、完全にあなたのデバイス内で動作」` | **Known sales-leaning; refine in copy pass** — Issue #152 author flagged this wording as too sales-y |

All three slots are localisable from day one (§5.5) — even when only
Japanese is shipped in Phase 2.

The copy pass in the implementation PR is explicitly empowered to
rewrite any of the three working drafts. The role definitions above are
the binding constraint; the exact words are not.

### 5.5 Multilingual posture

- **Phase 2 ship**: Japanese only. JA entries in
  `Localizable.xcstrings` for slots A/B/C. Demo YAML files are JA
  recordings (`metadata.language: ja`).
- **EN scaffolding**: the localisation keys exist in
  `Localizable.xcstrings` from day one, with EN entries left as stubs
  (either a literal `—` placeholder or the JA text with a
  `TODO(localisation)` comment — implementation chooses the more
  consistent pattern with rest of the app).
- **Phase 3 (future)**: EN demo recordings bundled alongside JA. Demo
  language selection is driven by device locale, with JA fallback for
  any non-EN-non-JA locale.

EN *demo recordings* are out of scope for Phase 2 regardless of whether
the app otherwise supports EN UI. Recording EN demos requires running
the scenarios against an EN-capable LLM prompt set, which is separate
curator work.

### 5.6 MVP preset candidates

Working candidate list for the first bundled set (final selection by
curator at recording time):

- **Word Wolf** — social deduction. Structurally ネタバレ-resistant
  (the "wolf" is only known post-discussion), which covers the
  Issue-#152 concern about spoilers.
- **Prisoner's Dilemma** — game-theory classic, crisp choose-action
  phases, clear scoreboard arc.
- **Non-existent animal brainstorm** — creative/collaborative flavour,
  globally legible premise, light tone.

Selection criteria for curator (not binding on any specific pick):

- Global legibility — no culture-specific references.
- Visible arc — starts, escalates, resolves within one screen's worth
  of scroll.
- Filter cleanliness — the recorded output passes `ContentFilter`
  without post-edit (if not, re-record).
- Duration — at 2× playback, one demo should read in under a minute so
  three demos fit comfortably in a short-to-medium DL window.

The curator picks **at least 3** for MVP shipping (§5.2). If three
candidates do not pass quality + floor criteria, the feature ships
disabled rather than with ≤ 2 demos (§5.3 fallback).

---

## 6. Dev-time Log Stash

Recording the initial MVP demo set and keeping the catalogue fresh
requires a workflow for capturing promising simulation runs as they
happen during development. Issue #152 explicitly flagged this as a
"don't wait until release to record" concern.

### 6.1 Current posture: deferred

This spec **does not** commit to a dev-time log-stash mechanism. The
design space (below) was surveyed during the Issue-#152 discussion and
closed as "return to this when the curator workflow needs formalising,
not before":

- **Candidate mechanism A**: an "Export for demo" button on the Past
  Results Viewer that writes the current simulation to disk in the §3
  YAML schema (bypassing the usual Markdown export flow). Curator
  promotes good stashes into the bundle via PR.
- **Candidate mechanism B**: a dev-only feature flag
  (`DEMO_CAPTURE=1` scheme env) that auto-copies every completed
  simulation's state as YAML to a known location.
- **Candidate mechanism C**: nothing special — curator manually
  re-runs scenarios and captures via the implementation PR's YAML
  export (when added).

### 6.2 Resume triggers

Revisit this decision when any of:

1. The MVP demo set needs expansion (e.g. 3 → 5) and manual
   re-recording proves friction-heavy.
2. A Phase 2.5+ `UserSimulationReplaySource` (§4.5) lands — at that
   point the YAML export flow exists and Candidate A becomes nearly
   free.
3. A curator decides to record demos in batch sessions rather than
   opportunistically, raising the value of automation (Candidate B).

Until one of those triggers fires, curators capture demos with
whatever ad-hoc method works (screen-recording, manual YAML editing,
etc.) and the captured files land in `Resources/DemoReplays/` via PR.

### 6.3 Boundary with Markdown export (#91 / #98)

The existing Markdown export (Share Sheet, Phase 2) serves a **different
purpose** and is not displaced by future YAML export work:

- Markdown export: user-facing share of simulation results (readable
  by humans, one-way).
- YAML export (hypothetical, triggered by §6.2): machine-ingestible
  round-trippable format for replay. This is the same format as the
  bundled demos (§3) — the future export is literally the inverse of
  the bundled-demo loader.

The two pipelines coexist without conflict; they serve different
audiences.

---

## 7. Risks and Consequences

Design-time risks identified for this feature. Most are addressed by
decisions already in §3-§6; this section consolidates the follow-up
vigilance required during implementation and after ship.

### 7.1 Schema drift on preset changes

**Risk.** A shipped preset YAML (e.g. `prisoners_dilemma`) is edited
without re-recording the bundled demos that reference it. Runtime
`yaml_sha256` check silently skips the drifted demos; if enough
skip, the loop falls to the §5.3 fallback.

**Mitigation.** §3.3 CI guard fails the build on bundled-demo-vs-shipped-
preset sha mismatch. The implementation PR ships this guard; without
it, drift lands silently.

### 7.2 Preset id collision

**Risk.** A gallery scenario's id collides with a bundled preset id (see
`docs/gallery/README.md` — the gallery has its own collision rules with
presets and other gallery entries). A demo referencing `preset_ref.id:
prisoners_dilemma` could in principle resolve to either the bundled
preset or a drifted gallery entry.

**Mitigation.** Demo loader resolves ids **only** against bundled
presets (not gallery). Gallery-installed scenarios are user-local and
never participate in demo playback. Implementation PR must honour this
in the id-resolution code path; tests assert that a gallery entry with
a colliding id does not shadow the bundled preset for demo purposes.

### 7.3 BG/FG playback jank

**Risk.** When the app backgrounds mid-playback (ADR-007 §3), the event
stream is suspended. On foreground return, a naive resume could jump
multiple turns at once (if the VM does not correctly pause its sleep)
or loop unexpectedly (if the state machine mis-handles re-entry).

**Mitigation.** §4.9 pins resume-from-position semantics. ADR-007 §3
pins the lifecycle interaction. Integration testing of BG/FG cycles is
a named acceptance criterion for the implementation PR.

### 7.4 LiteRT-LM migration impact on recorded YAML

**Risk.** ADR-002 forecasts migration from llama.cpp to LiteRT-LM when
the Swift SDK and iOS GPU support ship. Recorded demo YAML files
capture the llama.cpp-era outputs. Post-migration, replay still works
(the format is LLM-agnostic) but the content might read as stale if
the migrated model's outputs differ qualitatively.

**Mitigation.** `metadata.recorded_with_model` (§3.2) preserves the
provenance. Post-migration, curator decides whether to re-record based
on qualitative comparison; the mechanism requires no code changes. A
future LiteRT-LM recording can coexist with llama.cpp recordings in
the bundle during the transition window.

### 7.5 Future user-replay with missing scenario definitions

**Risk.** When `UserSimulationReplaySource` (§4.5) lands, it will try
to resolve `SimulationRecord.scenarioId` to a `Scenario`. If the user
deleted the referenced scenario (or the scenario's YAML changed such
that the saved `SimulationRecord.stateJSON` no longer type-matches),
replay will either fail or render incorrectly.

**Mitigation.** Deferred to Phase 2.5+ implementation — this spec only
scaffolds the protocol. The future implementation is expected to:
(a) refuse to build the source with a user-facing "this simulation
cannot be replayed" message; (b) surface a repair path (re-install the
scenario, or dismiss).

### 7.6 MVP floor compliance at curation time

**Risk.** Curator records 2 demos, calls them "good enough", ships
with `DemoReplays/` holding 2 files. §5.2 floor (≥ 3) is violated at
merge time, not caught by the drift-guard script (which checks sha
alignment, not count).

**Mitigation.** Implementation PR's CI adds a count check alongside
the sha drift check. Both are part of the same script, both hard-fail
the build.

### 7.7 Marketing / recording re-use surface

**Risk.** Bundled demos serve dual purpose — DL-time playback AND
external marketing (X / YouTube screen capture). A recording
optimised for silent 2×-playback might not read well in a
social-media context (too fast, no narration).

**Mitigation.** Curator evaluates recordings against both use cases at
selection time (§5.6 criteria). This is a curation-process concern,
not a technical risk; flagged here so it is not forgotten in the
curator workflow.

### 7.8 Accessibility

**Risk.** Fixed 2× playback with no user controls is hostile to users
who need slower pacing for cognitive or visual reasons. Phase 2 ships
without accessibility toggles.

**Mitigation.** This risk is accepted for Phase 2. The §4.9 state
machine can add a "manual pause / slow" control surface in a later
revision without changing the data format or VM architecture. Record
this as a follow-up consideration for accessibility-pass work.
