# Pastura — Product Roadmap

> Last updated: 2026-04-14
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
| In-app scenario generation (Cloud API)   | High     | Planned     | Claude/Gemini API for natural language → YAML |
| `conditional` phase type                 | Medium   | Planned     | Dynamic branching based on state         |
| `event_inject` phase type                | Medium   | Planned     | Random event injection mid-simulation    |
| `reflect` phase type                     | Medium   | Planned     | Agent self-reflection / memory compaction|
| Custom score_calc logic                  | Medium   | Planned     | User-defined scoring expressions         |
| Scenario sharing (Share Board)           | Medium   | In progress | Read-only curated gallery (#87). User submissions / ratings / share sheet deferred to Phase 3 marketplace. |
| E4B model switching                      | Low      | Planned     | Higher quality option for 12GB+ devices  |
| Inference speed display                  | Low      | Planned     | tok/s, time per inference in UI          |

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
| Scenario rankings / popular templates| Trending, most-run, highest-rated          |
| Simulation result auto-summary       | LLM-generated summary of what happened     |
| Relationship graph visualization     | Agent interaction network diagram          |
| Android support                      | Kotlin + LiteRT-LM Android SDK            |
| PC companion app                     | Python CLI or Tauri/Electron GUI           |
| Localization (English)               | Expand beyond Japanese-speaking users      |

---

## Platform Expansion Strategy

```
Phase 1: iOS only (Swift + SwiftUI)
Phase 2: iOS + background execution (iOS 26)
Phase 3: iOS + Android (Kotlin, LiteRT-LM Android SDK)
         PC via Python CLI (already exists as prototype)
Future:  KMP shared Engine, platform-specific UI and LLM layers
```

## Scope Decision Quick Reference

When evaluating whether to include a feature:

1. Is it in the Phase 2 planned features table with status "In progress"? → **Do it**
2. Is it in the Phase 2 table with status "Planned" but not started? → **Ask first**
3. Is it a Phase 3 feature? → **Don't do it, reference this doc**
4. Is it unlisted? → **Ask before implementing.** Default to deferring.
