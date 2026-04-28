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
- **Past results — code-phase events** — score_calc / scenario gen events in past-results viewer (#102/#113)

## Language Rules

- Conversation: **Match the user's language.** No project-level pin — defer to the operator's personal CLAUDE.md if a default is configured.
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

- **Automated hooks** (`.claude/settings.json`): On file edit (`PostToolUse` Edit|Write), `swift-format` + `swiftlint --fix` auto-format. On `git commit` (`PreToolUse`), `swiftlint lint --strict` + `xcodebuild build` run and block the commit on lint violations or compile errors. When the staged diff touches `docs/blocklist/source.json` or `Pastura/Pastura/Resources/ContentBlocklist.json`, `bash scripts/build-blocklist.sh --check` also runs (requires `brew install jq`); CI mirrors the same check.
- **Error types:** Layer-specific — `SimulationError` (Models, co-located with `SimulationEvent`),
  `LLMError` (LLM), `DataError` (Data). App layer catches and maps to UI presentation.
- **Error message i18n prep:** On `LocalizedError`-conforming types (`SimulationError`, `LLMError`, `DataError`, ...), wrap `errorDescription` literals in `String(localized: "...")`. Tests assert via `.contains(...)` partial matching, not equality. Keeps the current English-only scope while making future translation additive.
- **Swift 6 Concurrency:** `Sendable` for cross-actor types, `@MainActor` for UI state,
  `AsyncStream` over callbacks. Engine/LLM work runs on non-main actors or default executor.
- **Default Actor Isolation:** Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  All types in `Models/`, `LLM/`, `Engine/`, and `Data/` **MUST** be marked `nonisolated` at the
  type level to avoid unnecessary MainActor binding.
  `Views/` and `App/` use the default (MainActor).
  Protocol-extension default implementations may additionally need explicit `nonisolated`
  when their body builds escaping closures — see `.claude/rules/llm.md`.
- **"Why" comments:** Non-obvious choices must have a comment explaining **why**, not what.
- **Observable bridge for non-`@Observable` state:** When an `@Observable` class exposes
  a computed property that reads mutable state from a `nonisolated` class / actor,
  bridge observation manually — `access(keyPath: \.prop)` in the getter and
  `withMutation(keyPath: \.prop)` around every write. Without this, SwiftUI observers
  don't get invalidated when the underlying state changes. Example:
  `SimulationViewModel.isPaused` bridges to `SimulationRunner.isPaused` (PR #216).

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
| LLM models         | Runtime-selectable GGUF (see `App/ModelRegistry.swift`) | ~2.5–3.1 GB each |

LLM backend: llama.cpp is the interim backend for TestFlight (Metal GPU, on-device).
Migrate to LiteRT-LM when Swift SDK + iOS GPU support ships.
See ADR-001 §7 for protocol design and ADR-002 for llama.cpp decision.

## Testing Strategy

Priority: JSONResponseParser → ScenarioLoader → TemplateExpander → PhaseHandlers → ScoreCalcHandler.

`MockLLMService` returns pre-defined responses in sequence for deterministic Engine tests.
UI tests are not required for MVP.

## Development Workflow

### Implementation Entry Point

`/orchestrate` is the only entry point for file edits, commits, branch
creation, and pushes in this repository.

**Why:** `main` is push-protected (PR required), and concurrent sessions
collide on shared files (`Pastura.xcodeproj/project.pbxproj`, DerivedData,
generated assets) without worktree isolation.

When the conversation transitions from discussion or investigation toward
such work, announce `/orchestrate` and start it — even if the user didn't
mention it. Match the user's language; English baseline:

> "Switching to `/orchestrate` for the implementation."

GitHub-side actions that produce no local commit are out of scope — issue
management, PR comments/reviews on others' PRs, label/milestone edits,
workflow dispatch, release creation, draft-state toggles, merging an
already-opened PR. Local read-only sync (`git fetch`, `git pull` on the
default branch, `gh pr checkout`) is similarly out of scope. When in
doubt, default to `/orchestrate`.

The rule does not re-trigger for actions taken from inside `/orchestrate`
itself or from any sub-agent it dispatches.

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
- **Closing issues in multi-PR splits:** GitHub auto-closes on any `Closes #N` / `Fixes #N` match in the PR body, ignoring qualifiers like "partially" or "PR1 of 3". In non-final PRs of a split, reference without a close-directive keyword (`See #N`, `Part of #N`, `Relates to #N`). Only the final PR should carry `Closes #N`. If auto-close fires by accident on a non-final PR, recover immediately: `gh issue reopen <N> --comment "still tracking remaining scope: ..."`.

### Test Execution

See `.claude/rules/xcodebuild-cli.md` for the full xcodebuild CLI playbook
(test execution commands, DerivedData layout, agent-session timeout/recovery).

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
│   ├── Editor/
│   ├── Simulation/
│   ├── Results/
│   ├── Components/    # shared UI building blocks
│   └── ...            # additional screens (Community, Import, Settings, ModelDownload, ModelSelection)
├── Utilities/
└── Resources/
    ├── Presets/              # Bundled YAML scenarios
    ├── DemoReplays/          # DL-time demo playback (ADR-007)
    └── ContentBlocklist.txt  # ADR-005 content safety

pages/                           # Public HTML deployed via .github/workflows/deploy-pages.yml
├── support/                     # ASC Support URL
└── legal/privacy-policy/        # App Store privacy policy URL
```

## Context-Specific Rules

`.claude/rules/` contains detailed rules with two loading modes:

**Path-scoped** (loaded only when editing matching files):

- `engine.md` — Engine + LLM source (`Pastura/Pastura/Engine/**`, `Pastura/Pastura/LLM/**`)
- `models-and-data.md` — Models + Data source (`Pastura/Pastura/Models/**`, `Pastura/Pastura/Data/**`)
- `presets.md` — Bundled scenario YAML (`Pastura/Pastura/Resources/**`)
- `testing.md` — Test target (`Pastura/PasturaTests/**`)
- `view-testing.md` — View test strategy: extract logic to unit-tests, narrow UI integration tests, no ViewInspector / snapshot (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**ViewModel.swift`). Decision record: [ADR-009](docs/decisions/ADR-009.md).

**Always-loaded** (no frontmatter `paths:` — relevant from any layer):

- `llm.md` — LLM-layer traps (e.g., `nonisolated` protocol-default impls that build escaping closures) can fire from any conformer, including types added in `App/` or test targets, so the rule must stay visible regardless of which file is being edited.
- `navigation.md` — `AppRouter` pattern: programmatic root-stack navigation goes through `router.push(_:)` / `router.pushIfOnTop(expected:next:)`, and `navigationDestination(item:|isPresented:)` is forbidden inside views pushed onto the root stack. Sheet-owned NavigationStacks are exempt. Always-loaded because view-placement decisions can originate from any feature directory.
- `xcodebuild-cli.md` — xcodebuild CLI playbook (test commands, DerivedData layout, timeout/recovery for agent sessions). Always-loaded because xcodebuild gotchas surface during worktree switches and CI debugging, not only when editing test files.

## File Naming

- Source: PascalCase matching primary type (e.g., `SpeakAllHandler.swift`)
- Tests: `<SourceFileName>Tests.swift`
- YAML presets: snake_case (e.g., `prisoners_dilemma.yaml`)

## Decision Records

Record architectural decisions in `docs/decisions/` as `ADR-NNN.md`.

**Editability window**: For recently-Accepted ADRs whose decisions have not yet shipped in code, prefer **in-place edits** when implementation planning surfaces a refinement. Use `§N. Amendment YYYY-MM-DD` sections only after the ADR's decisions have been implemented — Amendment text doubles reviewer overhead on every cross-section read.

## Reference Documents

| Document                              | Content                                     |
|---------------------------------------|---------------------------------------------|
| `docs/ROADMAP.md`                     | Phase scope, Go/No-Go criteria              |
| `docs/decisions/ADR-001.md`           | Phase 1 architecture decisions (12 ADRs)    |
| `docs/decisions/ADR-002.md`           | llama.cpp interim LLM backend decision      |
| `docs/decisions/ADR-003.md`           | BG execution (iOS 26 BGContinuedProcessingTask) |
| `docs/decisions/ADR-004.md`           | Multi-platform strategy (Draft)             |
| `docs/decisions/ADR-005.md`           | Content safety architecture (App Store review) |
| `docs/decisions/ADR-006.md`           | Cloud API implementation details (Phase 3; reserved — not yet written; see ADR-005 §7.5) |
| `docs/decisions/ADR-007.md`           | DL-time demo replay — iOS lifecycle (#152)  |
| `docs/decisions/ADR-008.md`           | Route identity vs render-time hints (`RouteHint<T>` pattern, #245) |
| `docs/decisions/ADR-009.md`           | View testing strategy (no ViewInspector / snapshot; #269) |
| `docs/specs/pastura-mvp-spec-v0_3.md` | MVP specification                                         |
| `docs/specs/demo-replay-spec.md`      | DL-time demo replay — data format + component design (#152) |
| `docs/specs/demo-replay-ui.md`        | DL-time demo replay — visual / behaviour spec (#164)        |
| `docs/specs/demo-replay-mockup-prompt.md` | Claude Design prompt for the DL-time demo visual exploration |
| `docs/design/design-system.md`        | Cross-screen design system (tokens, philosophy, components) |
| `docs/design/demo-replay-reference.html` | DL-time demo visual reference prototype (HTML)             |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |
