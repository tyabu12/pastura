# CLAUDE.md — Pastura Development Guide

> This file is the primary reference for Claude Code when working on the Pastura project.
> Read this file in full before starting any task.

## Current Phase

**Phase 1: MVP development** — See `docs/ROADMAP.md` for phase definitions and Go/No-Go criteria.

## Language Rules

- Conversation with user: **Japanese**
- Code, commit messages, comments, documentation: **English**

## Project Overview

Pastura ("pasture" in Latin) is an iOS app for running AI multi-agent simulations on-device.
Users define scenarios in YAML; the app executes them using a local LLM (Gemma 4 E2B via LiteRT-LM)
with zero cost and full offline capability.

**Core metaphor:** Users are ranchers who release AI agents into a pasture (scenario) and observe
what happens. The value comes from experimental design and unexpected results, not from LLM output quality.

## Architecture

```
┌──────────────────────────────────────────────┐
│                SwiftUI Views                 │
│  Home → Detail → Import → Simulation → Results│
├──────────────────────────────────────────────┤
│              App / ViewModel                 │
│  Receives SimulationEvent via AsyncStream    │
│  Applies ContentFilter, persists to DB       │
├────────────┬─────────────────┬───────────────┤
│   Engine   │                 │     Data      │
│            │                 │               │
│  Scenario  │ SimulationState │  GRDB/SQLite  │
│  Loader    │ (Codable)       │               │
│            │                 │  Scenario     │
│  Phase     │  ── no dep ──>  │  Simulation   │
│  Dispatcher│                 │  Turn         │
│            │                 │  Repository   │
│  Prompt    │                 │               │
│  Builder   │                 │  Preset       │
│            │                 │  Loader       │
├────────────┴─────────────────┴───────────────┤
│                    LLM                       │
│  LLMService (protocol)                       │
│  ├── LiteRTLMService  (production, pending)  │
│  ├── OllamaService    (dev/Simulator)        │
│  └── MockLLMService   (tests)                │
│                                              │
│  JSONResponseParser / RetryPolicy            │
├──────────────────────────────────────────────┤
│                   Models                     │
│  Scenario, Persona, Phase, PhaseType         │
│  TurnOutput, SimulationState, etc.           │
└──────────────────────────────────────────────┘
```

## Hard Rules

1. **No force unwrap (`!`)** — Use `guard let`, `if let`, or `?` operator. Test code is exempt.
2. **No Engine → Data import** — Engine communicates via emitter closures. The App layer bridges Engine and Data.
3. **Doc comments on public protocols and types** — Required for future SPM module extraction.

## Dependency Rules (STRICT)

These rules prepare for future SPM module extraction. Violations are bugs.

```
Models/    → depends on nothing
LLM/       → depends on Models only
Engine/    → depends on LLM and Models. NEVER depends on Data.
Data/      → depends on Models only
Views/     → may depend on everything
App/       → may depend on everything
Utilities/ → depends on nothing
```

Engine communicates results via an emitter closure (which feeds AsyncStream).
The App/ViewModel layer receives events and writes to the database.
Engine never imports anything from Data/.

## Confirmation Policy

- Confirm with user before adding new SPM dependencies
- When uncertain about direction or trade-offs, always ask before proceeding
- Major changes to public protocol signatures require user approval
- When the current task reveals a need for significant design changes beyond the current scope, stop and report to the user before proceeding

## Access Modifiers

In preparation for future SPM module splits:
- All protocol definitions: `public`
- All types in Models/: `public`
- Internal implementation details: `internal` (default)

## Swift Coding Conventions

- **Formatting:** `swift-format` + `swiftlint --fix` auto-applied via hooks on every file edit.
- **Error types:** Layer-specific, not a unified app-wide type.
  - `SimulationError` (Engine), `LLMError` (LLM), `DataError` (Data)
  - App layer catches and maps to UI presentation
- **Swift 6 Concurrency:**
  - All types crossing actor boundaries must be `Sendable`
  - UI-bound state uses `@MainActor`
  - Engine/LLM work runs on non-main actors or default executor
  - Prefer `AsyncStream` over callback-based APIs
- **"Why" comments:** Non-obvious implementation choices must have a comment explaining **why**, not just what. Future readers (including LLMs) rely on these to understand intent.

## Tech Stack

| Component          | Choice                        | Version    |
|--------------------|-------------------------------|------------|
| Language           | Swift                         | 6.x       |
| UI                 | SwiftUI                       |            |
| Min iOS            | 17.0                          |            |
| YAML parser        | Yams                          | 6.2.1     |
| SQLite             | GRDB                          | 7.10.0    |
| LLM (production)   | LiteRT-LM iOS SDK (pending)  |            |
| LLM (dev)          | Ollama via OpenAI-compat API  |            |
| LLM (test)         | MockLLMService                |            |

## LLM Backend Strategy

The LiteRT-LM Swift SDK is not yet released ("Swift APIs coming soon" as of 2026-04).
Development proceeds with OllamaService. Integration order for production:

1. LiteRT-LM Swift SDK (adopt immediately upon release)
2. LiteRT-LM C API wrapper (c/engine.h, Swift C interop)
3. MediaPipe LLM Inference API (deprecated but iOS-ready, last resort)

The LLMService protocol abstracts all backends. Switching backends has ZERO impact
on Engine or UI code.

### LLMService Protocol

```swift
public protocol LLMService: Sendable {
    func loadModel() async throws
    func unloadModel()
    var isModelLoaded: Bool { get }
    func generate(system: String, user: String) async throws -> String
}
```

Model loading happens at simulation start. Unload after simulation completes.
On `didReceiveMemoryWarning`, unload immediately. Timing is adjustable without
changing the protocol — only the call site in App/ needs to change.

## Scope Boundaries

For phase boundaries, Go/No-Go criteria, and "is this feature in MVP?" decisions,
see `docs/ROADMAP.md`. If a requested feature is listed under Phase 2 or Phase 3,
do not implement it — reference the roadmap and defer.

## Testing Strategy

Priority order:
1. JSONResponseParser — all E2B output edge cases from Python prototype
2. ScenarioLoader — invalid YAML rejection, edge cases
3. TemplateExpander — variable expansion, undefined variables
4. PhaseHandlers — each type with MockLLMService
5. ScoreCalcHandler — scoring correctness

MockLLMService must exist from day one. It returns pre-defined responses
in sequence, enabling deterministic Engine tests without any LLM.

UI tests are not required for MVP.

## File Naming Conventions

- Source files: PascalCase matching the primary type (e.g., `SpeakAllHandler.swift`)
- Test files: `<SourceFileName>Tests.swift` (e.g., `JSONResponseParserTests.swift`)
- YAML presets: snake_case (e.g., `prisoners_dilemma.yaml`)

## Platform Strategy

MVP is iOS-only (Swift + SwiftUI).
Scenario definitions (YAML) and Engine logic are kept language-agnostic
to minimize future porting cost.
LiteRT-LM has official SDKs for Android (Kotlin), JVM Desktop, Python, and iOS (Swift, pending).
The Python prototype (among_them_prototype.py) serves as a PC reference implementation.

## Development Workflow

### TDD Approach

All Engine and LLM layer code is developed test-first:

1. **Write a failing test** using MockLLMService (for LLM-dependent code) or direct input (for pure logic)
2. **Write minimal implementation** to make the test pass
3. **Refactor** while keeping tests green
4. **Run SwiftLint** to check style

UI and Data layers follow a lighter approach: implement first, add tests for non-trivial logic.

### Recommended Implementation Order

Phase 1 development proceeds bottom-up to ensure each layer is tested before the next:

```
1. Models/           — Domain types (Scenario, Phase, TurnOutput, SimulationState)
2. LLM/              — MockLLMService, JSONResponseParser, RetryPolicy, OllamaService
3. Engine/            — ScenarioLoader, TemplateExpander, PhaseHandlers, SimulationRunner
4. Data/              — GRDB setup, repositories, PresetLoader
5. Views/             — SwiftUI screens, wired to Engine + Data
6. App/               — ContentFilter, AppState, navigation, model lifecycle
7. Integration test   — Full scenario run with OllamaService on Simulator
```

### Git Conventions

- **Branch naming:** `feature/<short-description>`, `fix/<short-description>`
- **Commit messages:** Conventional Commits with a single emoji prefix.
  Keep subject under 72 chars; add a body when the "why" isn't obvious.
  - `✨ feat: add SpeakAllHandler with tests`
  - `🐛 fix: strip thinking tags in JSONResponseParser`
  - `♻️ refactor: wire SimulationView to AsyncStream`
- **Commits should be small and focused** — one logical change per commit

### Test Execution

```bash
# Destination (Simulator)
DEST='platform=iOS Simulator,name=iPhone 16'

# Run all tests
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST"

# Run specific test class
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST" \
  -only-testing PasturaTests/JSONResponseParserTests

# Run a single test method
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST" \
  -only-testing PasturaTests/JSONResponseParserTests/testStripThinkingTags
```

## Decision Records (ADR)

- Record architectural decisions in `docs/decisions/` as ADR
- Filename format: `ADR-NNN.md` (e.g., `ADR-001.md`)

## Reference Documents

| Document                                    | Content                                    |
|---------------------------------------------|--------------------------------------------|
| `docs/ROADMAP.md`                           | Phase definitions, scope, Go/No-Go criteria|
| `docs/decisions/ADR-001.md`                 | Phase 1 architecture decisions             |
| `docs/specs/pastura-mvp-spec-v0_3.md`       | MVP specification (v0.3.0)                 |
| `docs/phase0/pastura-phase0-assessment.md`  | Phase 0 completion assessment              |
| `docs/phase0/pastura-scenario-prompt.md`    | Scenario generation prompt template        |
| `docs/phase0/among-them-feasibility.md`     | Technical feasibility analysis             |
| `docs/prototype/among_them_prototype.py`    | Python prototype (reference implementation)|

## Directory Structure

```
Pastura/
├── PasturaApp.swift
├── App/                          # App-level state, navigation
├── Engine/                       # Scenario engine (core logic)
│   ├── ScenarioLoader.swift
│   ├── SimulationRunner.swift
│   ├── PhaseHandler.swift        # Protocol definition
│   ├── Phases/                   # One file per phase type
│   ├── ScoringLogic/             # score_calc implementations
│   ├── PromptBuilder.swift
│   ├── TemplateExpander.swift
│   └── SimulationState.swift
├── LLM/                          # LLM inference layer
│   ├── LLMService.swift          # Protocol
│   ├── LiteRTLMService.swift     # Production (when SDK available)
│   ├── OllamaService.swift       # Development
│   ├── JSONResponseParser.swift
│   └── RetryPolicy.swift
├── Data/                         # Persistence
│   ├── Database.swift
│   ├── Models/                   # DB record types
│   ├── ScenarioRepository.swift
│   ├── SimulationRepository.swift
│   └── PresetLoader.swift
├── Models/                       # Domain models (DB-independent)
├── Views/                        # SwiftUI screens
│   ├── Home/
│   ├── ScenarioDetail/
│   ├── Import/
│   ├── Simulation/
│   ├── Results/
│   └── Components/
├── Utilities/
│   ├── ContentFilter.swift
│   └── DebugLogger.swift
├── Resources/
│   ├── Presets/                  # Bundled YAML scenarios
│   └── scenario_prompt_template.txt
└── Tests/
    ├── EngineTests/
    ├── LLMTests/
    └── DataTests/
```

## Rules Reference

| File | Scope | Loaded when |
|------|-------|-------------|
| `.claude/rules/engine.md` | Engine design, phase types, SimulationEvent, JSON parser, content filter, scoring | Editing `Pastura/Pastura/Engine/**`, `Pastura/Pastura/LLM/**` |
| `.claude/rules/models-and-data.md` | Data types (TurnOutput, SimulationState), DB schema | Editing `Pastura/Pastura/Models/**`, `Pastura/Pastura/Data/**` |
| `.claude/rules/presets.md` | Preset YAML scenario definitions (prisoners_dilemma, bokete) | Editing `Pastura/Pastura/Resources/**` |

## Skills Reference

| Skill | Description | Usage |
|-------|-------------|-------|
| `/implement` | Orchestrate full dev workflow: plan → issue → worktree → TDD → review → PR | `/implement <description>`, `/implement #N`, `/implement phase N` |
| `/write-adr` | Generate an ADR and save to `docs/decisions/` | `/write-adr <title>` |

