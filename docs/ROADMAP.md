# Pastura — Product Roadmap

> Last updated: 2026-04-25
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
| `event_inject` phase type                | Medium   | Done        | Random extraData-string injection into `state.variables` (default key `current_event`); Models→Engine→App→Views→Preset full-stack incl. word_wolf mid-flow showcase + demo replay re-record + bundled-demo phase_index alignment CI test (#256) |
| `reflect` phase type                     | Medium   | Planned     | Agent self-reflection / memory compaction|
| Custom score_calc logic                  | Medium   | Planned     | User-defined scoring expressions         |
| Localization (i18n: ja / en)             | High     | Planned     | App Store launch blocker (Steps A / B-1a / B-1b / C-1 / C-2 / D required); Step E is post-release polish. Promoted from Phase 3 on 2026-04-29. See § Localization Plan below. |
| Scenario sharing (Share Board)           | Medium   | Done (read-only) | Read-only curated gallery shipped (#87/#93). User submissions / ratings deferred to Phase 3 marketplace. |
| Scenario deep link (`pastura://` scheme) | Medium   | Done        | 1-tap install from external contexts (SNS, QR, blog). IDs resolved through the curated gallery index only — no arbitrary URL fetch, no auto-execute. Preview via `GalleryScenarioDetailView` with external-link origin banner (#88). Universal Links / QR code generation deferred. |
| Simulation result export (Markdown)      | Medium   | Done        | Share Sheet export including code-phase results (#91/#98) |
| Past results — code-phase event display  | Medium   | Done        | Score_calc / scenario gen events shown in past-results viewer (#102/#113) |
| YAML simulation replay primitive         | Medium   | Done        | Past Results YAML exporter + `YAMLReplaySource` importer primitive shipped (#175). Foundation for DL demo replay and future user-replay (spec §4.4 / §4.5). Replay gallery / Share Board integration deferred to Phase 3. |
| DL-time demo replay                      | Medium   | Done        | Bundled YAML replays during model download — end-to-end: spec + ADR-007 (#153), VM + Source (#186), host view + UI components (#197), wire into `.needsModelDownload` (#200), bundled YAMLs + CI drift guard (#205). |
| Multi-model support (Qwen / E4B / other) | Medium   | Done        | Dual-model catalog shipped (Gemma 4 E2B + Qwen 3 4B Q4_K_M) via the `ModelDescriptor` / `ModelRegistry` abstraction over `LLMService` (ADR-001 §7 / ADR-002): plumbing — descriptor, multi-model storage, sequential download, legacy Gemma file auto-recognition (#206); UI — first-run model picker (`AppState.needsModelSelection`), Settings → Models active-model switch + delete, race-prevention via `SimulationActivityRegistry` (#218). Tracking issue #203. E4B and additional models remain forward-looking; add a new `ModelDescriptor` entry to `ModelRegistry` when a model is approved for shipment. |
| Inference speed display                  | Low      | Done        | tok/s display + simulation playback UX (#99) |

### Technical Debt to Address
- Evaluate SPM module split (if file count > 100)
- **Migrate LLM backend from llama.cpp to LiteRT-LM** when Swift SDK + iOS GPU ships (see ADR-002)
- Conversation compaction (LLM-based summarization of old logs)
- Performance profiling on real devices (thermal, battery)
- **Remote model manifest** — currently `ModelRegistry` pins each entry's download URL, file size, and SHA-256 at compile time (originally tracked in #82). On-device-only inference + iOS sandboxing neutralizes the supply-chain exfiltration side; the residual risk (a crafted GGUF exploiting llama.cpp's parser) is shared with every on-device GGUF and not specific to dynamic metadata. Dynamic fetch (HuggingFace API) would let model updates ship without an app release but introduces non-determinism across users and a runtime dependency on a network call before download. Revisit when the model-update cadence makes the app-update tax meaningful.
- **Model switch deferred-apply UX** — Settings → Models currently swaps the active model instantly in UserDefaults; the actual model load happens at the next `SimulationViewModel.run()`. For users on the slowest devices this can produce a perceptible first-run latency spike after switching. Polish follow-up (#203): surface the load cost explicitly via a confirmation UI, or pre-warm the new model on switch.

### App Store Release Prep

First App Store submission depends on a set of cross-cutting blockers tracked in [ADR-005 §9.2](decisions/ADR-005.md#92-sub-issue-master-index) (content safety, encryption declaration, support URL, privacy manifest, etc.). Privacy policy work was not captured when ADR-005 was first written and is tracked separately in #233:

- [x] Draft privacy policy (`pages/legal/privacy-policy/index.html`)
- [x] Host the policy at `https://tyabu12.github.io/pastura/legal/privacy-policy/` via GitHub Pages
- [ ] Register the URL in App Store Connect → App Information → Privacy Policy URL
- [ ] Answer the App Privacy Details questionnaire ("Data Not Collected", per `PrivacyInfo.xcprivacy`)
- [x] Add in-app Settings → "Privacy Policy" link (Guideline 5.1.1: "easily accessible")

Custom EULA is intentionally deferred — Apple's [Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) auto-applies; revisit if Phase 3 introduces server-side data flows (gated on ADR-006).

### Localization Plan

> Promoted from Phase 3 on 2026-04-29. Reason: App Store release readiness for English-speaking users. Tracking issue #276.

i18n is split into staged Steps so the harder design questions (per-language YAML, cross-language simulation) can be sequenced after the App Store launch surface. **Minimum English App Store release ships Steps A + B-1a + B-1b + C-1 + C-2 + D** in dependency order; Step E is a post-release polish iteration.

#### Dependency graph

```
ROADMAP commit (#276)
  → Pre-ADR-010 stub PR
        + CLAUDE.md "Completed in Phase 2 so far" line
        + dependency-graph corrections (this section, if needed)
  → Step A (A-1 / A-2 PR split recommended) ⫶ Step B-1a (parallel)
  → Step B-1b (after A — UI must be English to capture screenshots)
  → Step C-1 (ADR-010 body + Engine dynamic localization)
  → Step C-2 (DB compat + drift script + demo replay + gallery + ADR-007 §3)
  → Step D (bundled English presets + English DL Demo Replay)
  → English App Store release
  → Step E (post-release polish)
```

#### Step table

| Step | Scope | Required for App Store | Complexity | Dependencies |
|------|-------|-----------------------|-----------|--------------|
| **A: UI shell + Error messages** | New `Localizable.xcstrings`; `knownRegions += ja`; convert ~58 hardcoded `Text("...")` to `String(localized:)`; wrap existing English `errorDescription` literals (`SimulationError` / `LLMError` / `DataError`) without text changes and add `ja` translations; audit `.claude/rules/navigation.md` scenarios 7 / 11–17 confirmed strings, `BackgroundSimulationManager` notifications, `ResultMarkdownExporter` headers, `ImportViewModel.scenarioGenerationPrompt` policy, and the `PromoCard` / `DLCompleteOverlay` deliberate-Japanese marketing copy; absorb the former B-2 scope (ContentBlocklist `lang` field documented in `docs/blocklist/README.md` — `ContentFilter` applies all entries regardless of UI locale); add `scripts/check_localization_coverage.py` to CI to fail when `ja` key coverage < 100%. **Out-of-Scope**: Engine prompt strings and scoring summaries (deferred to Step C). **DoD additions**: each audit item logs a (keep / translate / replace-on-en) decision in the PR description (no deferrals); `errorDescription` text remains unchanged (wrap-only); audit work is two-phase — (a) wrap existing English in `String(localized:)`, then (b) author the `ja` translations. PR-level split into A-1 (xcstrings + UI shell `ja` + B-2 docs) and A-2 (error i18n + audit + CI coverage) is recommended. | Required | Medium | Pre-ADR-010 stub |
| **B-1a: Store metadata + legal pages** | App Store Connect metadata (description, keywords, screenshot captions) in ja and en; Japanese versions of `pages/legal/privacy-policy/` and `pages/support/`. | Required | Low | None (parallel with A) |
| **B-1b: English screenshots** | Capture App Store screenshots with the English UI rendered. Cannot proceed before A — this is the only hard cross-step gate inside B-1. | Required | Low | **A complete** |
| **C-1: ADR-010 body + Engine dynamic localization** | ADR-010 body (Option B: per-language YAML files; `simulation_language` field schema — parse / validate only, wiring deferred to E; per-language scenario IDs with gallery curation aliases; `ContentFilter` continues full-set application regardless of UI locale). Dynamic localization of Engine hardcoded Japanese (`PromptBuilder` system / section / rule strings, `SpeakAllHandler` / `SpeakEachHandler` / `VoteHandler` defaults, `WordwolfJudgeLogic` summaries — ~10 sites total). Maintain `nonisolated` on Engine types. **Test compatibility (DoD)**: existing Japanese assertions in `PromptBuilderTests` / `SimulationRunnerTests` keep passing via the `scenario.language = "ja"` path; new `language = "en"` cases are added so both go green. | Required | High | A |
| **C-2: DB compat + drift + demo replay language selection + gallery** | Phase 1 existing scenario IDs (`word_wolf` etc.) preserved without breaking Past Results — alias or migration confirmed in ADR-010. `scripts/check_demo_replay_drift.py` `REQUIRED_LANGUAGE` hardcode replaced with `ALLOWED_LANGUAGES = {"ja", "en"}` (C-2 alone keeps `ja`-only verification green; Step D adds `en` demos and the script gains a second target). ADR-007 §3 amended with the demo replay language-selection logic. `docs/gallery/README.md` adds a language field. | Required | High | C-1 |
| **D: Bundled English presets + English DL Demo Replay** | English versions of the 4 bundled presets (`*_en.yaml`); English DL Demo Replay (device `ja` → ja, `en` → en, otherwise → en fallback); preset list UI prioritizes the device-language match. | Required | Medium-High | C-2 |
| **E: Cross-language simulation** | Wire `simulation_language` override into the Engine; implement LLM-output-language enforcement. **DoD (measurable)**: each English bundled preset achieves JSON parse success ≥ N% and target-language adherence ≥ M% on Qwen 3 4B Q4_K_M. The specific N, M values and the language detector (Apple `NLLanguageRecognizer` / cld3 / langdetect — TBD) are confirmed in ADR-010. The benchmark harness (`PasturaTests/Localization/LanguageAdherenceBenchmark.swift` etc.) is built within Step E, gated by an env var (mirroring `OLLAMA_INTEGRATION`), CI-disabled by default. | Post-release (strongly recommended) | High | D |

#### Language-resolution priority (3 layers, confirmed in ADR-010)

`simulation_language` (Step E wires) > `scenario.language` (Step C introduces) > `Bundle.main.preferredLocalizations` (Step D preset-list UI only).

#### Pre-ADR-010 stub (precedes Step A)

A short follow-up PR creates `docs/decisions/ADR-010.md` (Status: Proposed) with the minimum decisions Step A needs, kept narrow so the body can still iterate freely:

1. Scenario YAML language field name (`language`) and default value
2. Phase 1 backward-compat rule (missing field ⇒ implicit `ja`)
3. Engine hardcoded-Japanese strategy (X: `Localizable.xcstrings`-based / Y: dynamic per `scenario.language`) — body confirms which; the stub records "TBD in body"
4. Engine layer is excluded from Step A's `Localizable.xcstrings`; `nonisolated` is retained

The stub PR also adds a "Localization in progress" line to CLAUDE.md "Completed in Phase 2 so far" and refines this dependency graph if the early decisions shift it.

### Phase 2 → Phase 3 Go Criteria

Phase 2 is complete when:

- Localization Plan Steps A / B-1a / B-1b / C-1 / C-2 / D are all merged.
- The English App Store submission has reached Approve. Quantitative signals (DL count, review count and content) are tracked separately as post-release polish indicators rather than Go gates.
- Phase 2 features already shipped (Visual Editor, BG execution, Multi-model, Share Board, DL Demo Replay, ...) have no critical regressions.
- Step E (Cross-language simulation) may run in parallel within Phase 2 but is **not** a completion gate.

---

## Phase 3: Community

**Goal:** Build a user community around scenario creation and sharing.

**Prerequisite:** Phase 2 features stabilized, active user base.

### Planned Features

| Feature                              | Notes                                      |
|--------------------------------------|--------------------------------------------|
| Scenario marketplace                 | Browse, rate, download community scenarios |
| In-app scenario generation (Cloud API)| Claude/Gemini API for natural language → YAML. Deferred from Phase 2 (2026-04-21) to avoid cost-runaway / API-key-leakage risk during initial App Store release, and to share server-side infrastructure (identity, rate-limit, quota) with the marketplace. Gated on ADR-006; engineering beyond API-contract exploration is out of scope until ADR-006 merges (ADR-005 §7.5). |
| Scenario rankings / popular templates| Trending, most-run, highest-rated          |
| Simulation result auto-summary       | LLM-generated summary of what happened     |
| Relationship graph visualization     | Agent interaction network diagram          |
| Android support                      | Direction under evaluation — see [ADR-004 (Draft)](decisions/ADR-004.md). Current lean: KMP-shared Engine + native Jetpack Compose UI + **llama.cpp via a KMP binding, unified with iOS during Phase 3.0** (ADR-004 §3.6). Synchronised LiteRT-LM migration once iOS Swift SDK + GPU ships. |
| PC companion app                     | Form factor decided at Phase 3.2 — KMP-shared Engine + Compose Desktop is the current lean (see ADR-004). LLM backend unified with iOS / Android during Phase 3.0 (llama.cpp via a KMP binding; ADR-004 §3.6). |
| Localization (English)               | **Promoted to Phase 2 on 2026-04-29** — see Phase 2 § Localization Plan. Reason: App Store release readiness for English-speaking users. Tracking issue #276. |
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
