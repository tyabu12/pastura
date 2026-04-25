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

- **Automated hooks** (`.claude/settings.json`): On file edit (`PostToolUse` Edit|Write), `swift-format` + `swiftlint --fix` auto-format. On `git commit` (`PreToolUse`), `swiftlint lint --strict` + `xcodebuild build` run and block the commit on lint violations or compile errors.
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

```bash
source "$(git rev-parse --show-toplevel)/scripts/sim-dest.sh"

# Run all tests
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" -derivedDataPath "$DERIVED_DATA"

# Run specific test class
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" -derivedDataPath "$DERIVED_DATA" \
  -only-testing PasturaTests/JSONResponseParserTests

# Run Ollama integration tests (requires local Ollama with target model pulled)
# Enable OLLAMA_INTEGRATION in scheme: Edit Scheme → Run → Environment Variables → toggle ON
xcodebuild test -scheme Pastura -project Pastura/Pastura.xcodeproj \
  -destination "$DEST" -derivedDataPath "$DERIVED_DATA" \
  -only-testing PasturaTests/OllamaIntegrationTests
# These tests are automatically skipped when OLLAMA_INTEGRATION is not enabled in the scheme.
```

#### DerivedData location

`sim-dest.sh` exports `DERIVED_DATA` pointing at `Pastura/DerivedData/` inside
the current worktree. Always pass `-derivedDataPath "$DERIVED_DATA"` to
`xcodebuild` so the CLI matches the Xcode.app Workspace-relative layout
configured in `project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`.
This keeps GUI and CLI builds sharing one cache per worktree and makes
`git worktree remove` auto-clean all build artifacts. Two gotchas:

- **Pass `-derivedDataPath` with a space**, not `=`. The `=` form is silently
  ignored by `xcodebuild` (known since Xcode 15.4).
- **CI is intentionally left on the default `~/Library/...` path** so its
  existing SPM cache (`actions/cache` keyed on that path) keeps hitting. If
  CI ever starts passing `-derivedDataPath`, update both cache paths in
  `.github/workflows/ci.yml` in the same PR.

#### Running xcodebuild from an agent session

`xcodebuild test` takes minutes. A few operational guardrails to avoid
burning wall-clock and orphaning processes:

**Prevention (do this up-front):**

- Narrow scope whenever possible — `-only-testing PasturaTests/<Suite>`.
- If the change doesn't touch UI code, add `-skip-testing:PasturaUITests`
  (UI tests are not required for MVP; CI will still cover them).
- Always pass an explicit bash `timeout` — the default 120s is shorter
  than even a focused suite. Guideline: `timeout: 180000` (3 min) for a
  single suite, `timeout: 600000` (10 min) for the full unit suite,
  `timeout: 900000` (15 min) when UI tests are included.
- For runs expected to exceed 5 minutes, prefer `run_in_background: true`
  and poll with Monitor / BashOutput rather than blocking the session.
- When piping through `tail` (e.g. `xcodebuild ... 2>&1 | tail -80`), the
  pipe's exit code is `tail`'s, not `xcodebuild`'s — a failed build reports
  `exit code 0`. Grep the tailed output for `** BUILD|TEST SUCCEEDED/FAILED **`
  or `xcodebuild: error:` before trusting the harness exit code, or use
  `set -o pipefail`. When the SUCCEEDED marker has been trimmed off entirely,
  extract the verdict from the xcresult bundle: `xcrun xcresulttool get test-results summary --path "$XCRESULT" --format json`.

**Recovery (if a run hangs or a retry immediately stalls):**

- The session's bash timeout kills the shell wrapper, but spawned
  `xcodebuild` / `testmanagerd` / `XCTRunner` processes can outlive it
  and keep the simulator destination busy. Subsequent `xcodebuild test`
  calls then queue behind them and appear to hang.
- Before killing, **read the full command lines** so you don't clobber a
  concurrent run from another worktree:
  `pgrep -af "xcodebuild|XCTRunner|testmanagerd"`.
- Only if you're sure every listed process belongs to your session:
  `pkill -f "xcodebuild test"`; then reset the simulator with
  `xcrun simctl shutdown "$(echo "$DEST" | sed -n 's/.*id=//p')"`.
- If UI tests fail with
  `FBSOpenApplicationServiceErrorDomain Code=1 — com.tyabu12.PasturaUITests.xctrunner`,
  try `xcrun simctl erase <UDID>` + retry **once**. Persistent failures
  are real bugs (signing, plist, or app-state regression), not flakes —
  do not swallow them.

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
| `docs/specs/pastura-mvp-spec-v0_3.md` | MVP specification                                         |
| `docs/specs/demo-replay-spec.md`      | DL-time demo replay — data format + component design (#152) |
| `docs/specs/demo-replay-ui.md`        | DL-time demo replay — visual / behaviour spec (#164)        |
| `docs/specs/demo-replay-mockup-prompt.md` | Claude Design prompt for the DL-time demo visual exploration |
| `docs/design/design-system.md`        | Cross-screen design system (tokens, philosophy, components) |
| `docs/design/demo-replay-reference.html` | DL-time demo visual reference prototype (HTML)             |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |
