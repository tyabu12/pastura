# Pastura — AIgazing simulator

> Read this file in full before starting any task.

## Current Phase

**Phase 2: Expansion** — See `docs/ROADMAP.md` for scope.
Phase 1 MVP shipped via TestFlight (conditional Go, 2026-04-13).
If a requested feature is listed under Phase 3, do not implement it — reference the roadmap and defer.

Completed in Phase 2 so far:
- **Visual Scenario Editor** — dual-mode form + YAML (#83)
- **Background execution** — iOS 26 BGContinuedProcessingTask + CPU inference (#84)
- **Share Board** — read-only curated scenario gallery (#87/#93)
- **Simulation result export** — Markdown via Share Sheet, incl. code-phase results (#91/#98)
- **Inference speed display** — tok/s + simulation playback UX (#99)

## Language Rules

- Conversation with user: **Japanese**
- Code, commit messages, comments, documentation: **English**

## Project Overview

Pastura is an iOS app for running AI multi-agent simulations on-device.
Users define scenarios in YAML; the app executes them using a local LLM
(Gemma 4 E2B via llama.cpp for TestFlight; LiteRT-LM planned as target backend)
with zero cost and full offline capability. MVP is iOS-only (Swift + SwiftUI).

## Architecture

See `docs/decisions/ADR-001.md` (Architecture Overview) for the full layer diagram.

Layers (top → bottom): **Views → App/ViewModel → Engine + Data → LLM → Models**.
Engine emits `SimulationEvent` via `AsyncStream`; the App/ViewModel layer receives events,
applies `ContentFilter`, and persists to the database.
LLM backends are abstracted behind `LLMService` protocol (see `LLM/LLMService.swift`).

## Hard Rules

1. **No force unwrap (`!`)** — Use `guard let`, `if let`, or `?`. Test code is exempt.
2. **No Engine → Data import** — Engine communicates via emitter closures. App layer bridges Engine and Data.
3. **Doc comments on public protocols and types** — Required for future SPM module extraction.

## Dependency Rules (STRICT)

Violations are bugs. These prepare for future SPM module extraction.

```
Models/    → depends on nothing
LLM/       → depends on Models only
Engine/    → depends on LLM and Models. NEVER depends on Data.
Data/      → depends on Models only
Views/     → may depend on everything
App/       → may depend on everything
Utilities/ → depends on nothing
```

## Confirmation Policy

- Confirm with user before adding new SPM dependencies
- When uncertain about direction or trade-offs, always ask before proceeding
- Major changes to public protocol signatures require user approval
- Significant design changes beyond the current scope: stop and report first

## Access Modifiers

- All protocol definitions: `public`
- All types in Models/: `public`
- Internal implementation details: `internal` (default)

## Swift Coding Conventions

- **Formatting:** `swift-format` + `swiftlint --fix` auto-applied via hooks on every file edit.
- **Error types:** Layer-specific — `SimulationError` (Models, co-located with `SimulationEvent`),
  `LLMError` (LLM), `DataError` (Data). App layer catches and maps to UI presentation.
- **Swift 6 Concurrency:** `Sendable` for cross-actor types, `@MainActor` for UI state,
  `AsyncStream` over callbacks. Engine/LLM work runs on non-main actors or default executor.
- **Default Actor Isolation:** Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  All types in `Models/`, `LLM/`, `Engine/`, and `Data/` **MUST** be marked `nonisolated` at the
  type level to avoid unnecessary MainActor binding.
  `Views/` and `App/` use the default (MainActor).
- **"Why" comments:** Non-obvious choices must have a comment explaining **why**, not what.

## Tech Stack

| Component          | Choice                        | Version   |
|--------------------|-------------------------------|-----------|
| Language           | Swift                         | 6.x       |
| UI                 | SwiftUI                       |           |
| Min iOS            | 17.0                          |           |
| YAML parser        | Yams                          | 6.2.1     |
| SQLite             | GRDB                          | 7.10.0    |
| LLM (TestFlight)   | llama.cpp via mattt/llama.swift | pinned   |
| LLM (target)       | LiteRT-LM iOS SDK (planned)  |           |
| LLM (dev)          | Ollama via OpenAI-compat API  |           |
| LLM (test)         | MockLLMService                |           |
| LLM model          | Gemma 4 E2B Q4_K_M (GGUF)    | ~3.1 GB   |

LLM backend: llama.cpp is the interim backend for TestFlight (Metal GPU, on-device).
Migrate to LiteRT-LM when Swift SDK + iOS GPU support ships.
See ADR-001 §7 for protocol design and ADR-002 for llama.cpp decision.

## Testing Strategy

Priority: JSONResponseParser → ScenarioLoader → TemplateExpander → PhaseHandlers → ScoreCalcHandler.

`MockLLMService` returns pre-defined responses in sequence for deterministic Engine tests.
UI tests are not required for MVP.

## Development Workflow

### TDD Approach

Engine and LLM layer: test-first (write failing test → minimal implementation → refactor).
Data and UI layers: implement first, add tests for non-trivial logic.

Implementation order: `Models → LLM → Engine → Data → Views → App → Integration test`

### Git Conventions

- **Branch:** `feature/<description>`, `fix/<description>`
- **Branch ops:** Prefer `git switch <branch>` / `git switch -c <branch>` over `git checkout`.
  Never use `git switch` with `--discard-changes`, `--force`, `-f`, or `-C` — they discard
  uncommitted work or overwrite branch refs.
- **Commits:** Conventional Commits with emoji prefix, under 72 chars.
  `✨ feat:`, `🐛 fix:`, `♻️ refactor:` — add body when "why" isn't obvious.
- **Small and focused** — one logical change per commit.

### Test Execution

```bash
source "$(git rev-parse --show-toplevel)/scripts/sim-dest.sh"

# Run all tests
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST"

# Run specific test class
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST" \
  -only-testing PasturaTests/JSONResponseParserTests

# Run Ollama integration tests (requires local Ollama with target model pulled)
# Enable OLLAMA_INTEGRATION in scheme: Edit Scheme → Run → Environment Variables → toggle ON
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj -destination "$DEST" \
  -only-testing PasturaTests/OllamaIntegrationTests
# These tests are automatically skipped when OLLAMA_INTEGRATION is not enabled in the scheme.
```

## Directory Structure

```
Pastura/
├── PasturaApp.swift
├── App/               # App-level state, navigation
├── Engine/            # Scenario engine (core logic)
│   ├── Phases/        # One handler per phase type
│   └── ScoringLogic/  # score_calc implementations
├── LLM/               # LLM inference layer
├── Data/              # Persistence (GRDB/SQLite)
│   └── Models/        # DB record types
├── Models/            # Domain models (DB-independent)
├── Views/             # SwiftUI screens
│   ├── Home/
│   ├── ScenarioDetail/
│   ├── Import/
│   ├── Simulation/
│   ├── Results/
│   └── Components/
├── Utilities/
└── Resources/
    └── Presets/        # Bundled YAML scenarios
```

## Context-Specific Rules

See `.claude/rules/` for detailed rules loaded automatically when editing Engine, LLM, Models, Data, or Resources files.

`navigation.md` documents the `AppRouter` pattern: programmatic root-stack
navigation goes through `router.push(_:)` / `router.pushIfOnTop(expected:next:)`,
and `navigationDestination(item:|isPresented:)` is forbidden inside views
pushed onto the root stack. Sheet-owned NavigationStacks are exempt.

## File Naming

- Source: PascalCase matching primary type (e.g., `SpeakAllHandler.swift`)
- Tests: `<SourceFileName>Tests.swift`
- YAML presets: snake_case (e.g., `prisoners_dilemma.yaml`)

## Decision Records

Record architectural decisions in `docs/decisions/` as `ADR-NNN.md`.

## Reference Documents

| Document                              | Content                                     |
|---------------------------------------|---------------------------------------------|
| `docs/ROADMAP.md`                     | Phase scope, Go/No-Go criteria              |
| `docs/decisions/ADR-001.md`           | Phase 1 architecture decisions (12 ADRs)    |
| `docs/decisions/ADR-002.md`           | llama.cpp interim LLM backend decision      |
| `docs/decisions/ADR-003.md`           | BG execution (iOS 26 BGContinuedProcessingTask) |
| `docs/decisions/ADR-004.md`           | Multi-platform strategy (Draft)             |
| `docs/specs/pastura-mvp-spec-v0_3.md` | MVP specification                                         |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |
