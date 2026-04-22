# Pastura — Product Roadmap

> Last updated: 2026-04-22
> This document defines phase boundaries and scope. When in doubt whether a feature
> belongs in the current phase, check here first.

---

## Phase 0: Prototype Validation ✅ Complete (Conditional Go)

**Duration:** Complete as of 2026-04-06

### What was validated
- YAML scenario engine works (8 phase types, declarative definition → execution)
- E2B JSON output stabilized (retry + parser hardening)
- Persona consistency improved with 【立場】【目的】 pattern
- Concept pivot: entertainment app → experiment platform
- Scenario generation prompt created and tested

### Remaining items (carry into Phase 1)
- Word Wolf E2B live test (preset #3 confirmation) ✅ Confirmed in PR #36
- E4B / Claude quality comparison (low priority)

### Key learnings (documented in pastura-phase0-assessment.md)
- speak_each rounds × main rounds multiplication is dangerous (93 min for 5×9)
- Vote candidate names must be explicit in system prompt
- 2–3 main rounds is the sweet spot
- Keep total inferences under 50

---

## Phase 1: MVP Development ✅ Complete

**Goal:** Build and ship a testable iOS app via TestFlight.

**Result:** Conditional Go (2026-04-13). Tester reaction positive but no organic scenario
creation observed. Decision: ship to App Store to gauge wider public reaction.

### Go/No-Go Criteria (evaluate after TestFlight)

**Go (proceed to Phase 2):**
- 3+ of 5 testers say "I want to create my own scenario"
- At least 1 user-created scenario emerges organically from testers
- Natural occurrence of "this would be fun with X" during testing

**No-Go (retreat or re-pivot):**
- Tester reaction is "meh, so what?" with no curiosity about experimentation
- YAML authoring barrier is too high — testers give up on creating scenarios
- E2B output is too noisy to be meaningful even as experimental observation

### MVP Scope

| Feature                        | Status   |
|--------------------------------|----------|
| Preset scenarios (2–3)         | Done     |
| YAML scenario import           | Done     |
| YAML validation + error display| Done     |
| All 8 phase types              | Done     |
| Foreground simulation execution| Done     |
| Real-time log display          | Done     |
| Inner thought (tap to reveal)  | Done     |
| Phase type visualization       | Done     |
| Scoreboard (modal)             | Done     |
| Playback controls (pause/speed)| Done     |
| Past results viewer            | Done     |
| Debug mode (raw JSON)          | Done     |
| NG word filter                 | Done     |
| Scenario gen prompt (copyable) | Done     |
| On-device LLM (llama.cpp)      | Done     |
| TestFlight distribution        | Done     |

---

## Phase 2: Expansion 🔧 In Progress

**Goal:** Lower barriers, expand capabilities, reach broader audience.

**Prerequisite:** Phase 1 Go decision from TestFlight feedback. ✅ Conditional Go (2026-04-13)

### Planned Features

| Feature                                  | Priority | Status      | Notes                                    |
|------------------------------------------|----------|-------------|------------------------------------------|
| Visual scenario editor (dual-mode)       | High     | Done        | Form + block UI with YAML mode toggle (#83) |
| Background execution (iOS 26)            | High     | Done        | BGContinuedProcessingTask + CPU inference in background (#84) |
| Real-time LLM token streaming            | High     | Done        | Token-by-token streaming via `LLMService.generateStream`; `LLMCaller` drains snapshots and emits partial events. ContentFilter applied to streaming snapshots (#119/#132/#140); reveal task kept alive across tokens (#147). |
| `conditional` phase type                 | Medium   | Done        | Nested-branch phase + Visual Editor support; includes `target_score_race` preset and conditional endings in `word_wolf` / `detective_scene` (#126/#141). |
| `event_inject` phase type                | Medium   | Planned     | Random event injection mid-simulation    |
| `reflect` phase type                     | Medium   | Planned     | Agent self-reflection / memory compaction|
| Custom score_calc logic                  | Medium   | Planned     | User-defined scoring expressions         |
| Scenario sharing (Share Board)           | Medium   | Done (read-only) | Read-only curated gallery shipped (#87/#93). User submissions / ratings deferred to Phase 3 marketplace. |
| Scenario deep link (`pastura://` scheme) | Medium   | Done        | 1-tap install from external contexts (SNS, QR, blog). IDs resolved through the curated gallery index only — no arbitrary URL fetch, no auto-execute. Preview via `GalleryScenarioDetailView` with external-link origin banner (#88). Universal Links / QR code generation deferred. |
| Simulation result export (Markdown)      | Medium   | Done        | Share Sheet export including code-phase results (#91/#98) |
| Past results — code-phase event display  | Medium   | Done        | Score_calc / scenario gen events shown in past-results viewer (#102/#113) |
| YAML simulation replay primitive         | Medium   | Planned     | Past Results YAML exporter + `YAMLReplaySource` importer primitive. Foundation for DL demo replay and future user-replay (spec §4.4 / §4.5). Replay gallery / Share Board integration deferred to Phase 3. Resumes spec §6.1 Candidate A (#164). |
| DL-time demo replay                      | Medium   | Planned     | Bundled YAML replays during model download; see ADR-007, `docs/specs/demo-replay-spec.md` (data/arch), `docs/specs/demo-replay-ui.md` (visual/behaviour), and `docs/design/design-system.md` (tokens). Non-blocking for App Store submission; implementation follows #148/#149 closure (#152). |
| Multi-model support (Qwen / E4B / other) | Medium   | Planned     | Additional on-device models for device-class fit + cross-model experimentation via the `LLMService` abstraction (ADR-001 §7 / ADR-002). Complements the offline-first story and provides "same scenario, different model" depth without cloud-cost / API-key risk. |
| Inference speed display                  | Low      | Done        | tok/s display + simulation playback UX (#99) |

### Technical Debt to Address
- Evaluate SPM module split (if file count > 100)
- **Migrate LLM backend from llama.cpp to LiteRT-LM** when Swift SDK + iOS GPU ships (see ADR-002)
- Conversation compaction (LLM-based summarization of old logs)
- Performance profiling on real devices (thermal, battery)

---

## Phase 3: Community

**Goal:** Build a user community around scenario creation and sharing.

**Prerequisite:** Phase 2 features stabilized, active user base.

### Planned Features

| Feature                              | Notes                                      |
|--------------------------------------|--------------------------------------------|
| Scenario marketplace                 | Browse, rate, download community scenarios |
| In-app scenario generation (Cloud API)| Claude/Gemini API for natural language → YAML. Deferred from Phase 2 (2026-04-21) to avoid cost-runaway / API-key-leakage risk during initial App Store release, and to share server-side infrastructure (identity, rate-limit, quota) with the marketplace. Gated on ADR-006; engineering beyond API-contract exploration is out of scope until ADR-006 merges (ADR-005 §7.5, §10). |
| Scenario rankings / popular templates| Trending, most-run, highest-rated          |
| Simulation result auto-summary       | LLM-generated summary of what happened     |
| Relationship graph visualization     | Agent interaction network diagram          |
| Android support                      | Direction under evaluation — see [ADR-004 (Draft)](decisions/ADR-004.md). Current lean: KMP-shared Engine + native Jetpack Compose UI + **llama.cpp via a KMP binding, unified with iOS during Phase 3.0** (ADR-004 §3.6). Synchronised LiteRT-LM migration once iOS Swift SDK + GPU ships. |
| PC companion app                     | Form factor decided at Phase 3.2 — KMP-shared Engine + Compose Desktop is the current lean (see ADR-004). LLM backend unified with iOS / Android during Phase 3.0 (llama.cpp via a KMP binding; ADR-004 §3.6). |
| Localization (English)               | Expand beyond Japanese-speaking users      |
| Early-termination phase type         | `conditional` branches but does not stop a simulation early — `rounds` still governs the loop. A new phase type (working name `terminate` / `break`) would let a branch signal "end the simulation now, run the remaining phases, then skip unrun rounds." Keeps `conditional` purely about evaluation + branching; termination is orthogonal. See PR #141 discussion. |

---

## Platform Expansion Strategy

```
Phase 1: iOS only (Swift + SwiftUI)
Phase 2: iOS + background execution (iOS 26)
Phase 3: iOS + Android + Desktop via KMP shared Engine (direction under evaluation)
         See ADR-004 (Draft) — platform-specific UI (SwiftUI / Compose / Compose Desktop)
         and unified llama.cpp LLM backend across all platforms
         during Phase 3.0 (via a llama.cpp KMP binding on Android / Desktop;
         ADR-004 §3.6). Migration to LiteRT-LM deferred until Google's
         iOS Swift SDK + GPU ships; at that point synchronised migration
         across platforms is the default, with per-platform timing
         reconsiderable after Phase 3.0 stabilises (ADR-002 §8.1).
         Final decision at Phase 2 → Phase 3 transition.
```

## Scope Decision Quick Reference

When evaluating whether to include a feature:

1. Is it in the Phase 2 planned features table with status "In progress"? → **Do it**
2. Is it in the Phase 2 table with status "Planned" but not started? → **Ask first**
3. Is it a Phase 3 feature? → **Don't do it, reference this doc**
4. Is it unlisted? → **Ask before implementing.** Default to deferring.
