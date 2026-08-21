# Pastura — AIgazing simulator

> Read this file in full before starting any task. Rules the compiler, SwiftLint, a pre-commit gate, or CI already enforce are not repeated here — the build tells you. What is here either fails silently or is a decision only a human can make.

## Current Phase

Phase 2 (Expansion) complete — v1.0 released to the App Store 2026-07-23. Phase 3 (Community) not entered. If a requested feature is listed under Phase 3 in `docs/ROADMAP.md`, defer it and say so.

## Language Rules

- Conversation: match the user's language.
- Code, commit messages, comments, documentation: English.

## Project Overview

iOS app that runs AI multi-agent simulations on-device. Users define scenarios in YAML; a local LLM (Gemma 4 E2B via llama.cpp) executes them offline at zero cost. Swift 6 + SwiftUI, iOS-only.

## Architecture

Layers, top → bottom: **Views → App/ViewModel → Engine + Data → LLM → Models** (`docs/decisions/ADR-001.md`). Engine emits `SimulationEvent` via `AsyncStream`; the App layer applies `ContentFilter` and persists. LLM backends sit behind the `LLMService` protocol (`LLM/LLMService.swift`).

README.md and CONTRIBUTING.md mirror Architecture, Hard Rules, Dependency Rules, Tech Stack, and Git Conventions — change both. Two mirrors are source-driven rather than section-driven: `App/ModelRegistry.swift` → README "Supported LLM models", and the i18n / `ContentBlocklist.json` procedures → CONTRIBUTING "Before your first PR".

## Hard Rules

1. **No force unwrap (`!`)** — `guard let`, `if let`, or `?`. Test code is exempt (SwiftLint `force_unwrapping`; nested configs exempt the test trees).
2. **No Engine → Data import** — Engine communicates via emitter closures; the App layer bridges.
3. **Doc comments on public protocols and types.**

## Dependency Rules (STRICT)

```
Models/      → depends on nothing
LLM/         → Models only
Engine/      → LLM and Models. NEVER Data.
Data/        → Models only
Views/, App/ → may depend on everything
Utilities/   → depends on nothing
```

## Access Modifiers

Protocol definitions and every type in `Models/` are `public`; everything else stays `internal`.

## Swift Coding Conventions

- **Default actor isolation is MainActor** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Every type in `Models/`, `LLM/`, `Engine/`, `Data/` is `nonisolated` at the type level. The traps that raise no diagnostic — a `nonisolated async` body running on the caller's executor, an unannotated ObjC protocol, a MainActor-inferred framework closure — are in `.claude/rules/swift-isolation.md`.
- **Observable bridge**: an `@Observable` class exposing state owned by a `nonisolated` class or actor must call `access(keyPath:)` in the getter and `withMutation(keyPath:)` around **every** write, or SwiftUI never invalidates. Example: `SimulationViewModel.isPaused`.
- **Logger privacy**: OSLog redacts `String` / `Substring` / `Error` interpolations as `<private>` in Release. Annotate non-`.debug` interpolations with `privacy: .public`; never interpolate user content (scenario text, agent output) — persist it via `TurnRecord` instead.
- **Bundle-ID suffix**: Debug builds ship as `app.pastura.Pastura.dev`. An identifier declared in `Info.plist` (e.g. `BGTaskScheduler`) must be `$(PRODUCT_BUNDLE_IDENTIFIER)` on both sides — a mismatch only logs and ships silently dead. A per-container identifier (a background `URLSession`) must **not** track the suffix, or renaming orphans in-flight downloads.
- **ADR-022-governed enums**: the no-default gate does not cover `== .<case>` predicates — grep `== .<case>` when adding a case (ADR-027).
- **Error types are per layer**: `SimulationError` (Models), `LLMError` (LLM), `DataError` (Data); the App layer maps them to UI. `errorDescription` literals go through `String(localized:)`; tests match with `.contains`, not equality.
- **User-facing strings** go through `String(localized:)` so they land in `Localizable.xcstrings` with a `ja` translation. Callsite conventions: `.claude/rules/i18n.md`, `i18n-ui.md`, `i18n-catalog.md` — the last loads only on a `Read` of the catalog, so read it explicitly before a scripted mutation.
- **"Why" comments** on non-obvious choices, addressed to the next editor — never a restatement of what the diff did.
- `Sendable` for cross-actor types, `@MainActor` for UI state, `AsyncStream` over callbacks.

## Tech Stack

| Component | Choice | Version |
|---|---|---|
| Language | Swift | 6.x |
| UI | SwiftUI | |
| Min iOS | 18.0 | |
| YAML parser | Yams | 6.2.2 |
| SQLite | GRDB | 7.11.1 |
| LLM (TestFlight) | llama.cpp via mattt/llama.swift | pinned |
| LLM (target) | LiteRT-LM iOS SDK (planned) | |
| LLM (dev) | Ollama via OpenAI-compat API | |
| LLM (test) | MockLLMService | |
| LLM models | Runtime-selectable GGUF (`App/ModelRegistry.swift`) | ~2.5–3.1 GB each |

llama.cpp is the interim backend (ADR-002); migrate to LiteRT-LM when its Swift SDK ships.

## Testing Strategy

Engine and LLM: test-first. Data and UI: implement first, then test non-trivial logic. Priority: JSONResponseParser → ScenarioLoader → TemplateExpander → PhaseHandlers → ScoreCalcHandler. `MockLLMService` returns scripted responses for deterministic Engine tests. UI tests are not required.

## Development Workflow

**`/orchestrate` is the only entry point for file edits, commits, branch creation, and pushes.** `main` is push-protected, and concurrent sessions collide on shared files without worktree isolation. When a conversation turns toward such work, announce it and start it. Out of scope: GitHub-side actions with no local commit (issues, PR comments, labels, merges) and read-only sync (`git fetch`, `git pull` on main, `gh pr checkout`). Exempt: the `/release` tag push and `/simplify-doc`'s prose-only edit + commit.

Implementation order: Models → LLM → Engine → Data → Views → App → integration test.

Local builds and tests go through `scripts/xcodebuild.sh` (`.claude/rules/xcodebuild-cli.md`). The git pre-commit hook (`./scripts/setup.sh` once per clone) runs the `scripts/*-gate.sh` sub-gates, plus SwiftLint and the build when the changeset touches iOS sources (`scripts/precommit-gate-classify.sh` decides); CI mirrors every check.

### Git Conventions

- Branches: `feature/<desc>`, `fix/<desc>`, `docs/<desc>`. Prefer `git switch`; never `--discard-changes`, `--force`, `-f`, or `-C`.
- Commits: Conventional Commits with an emoji prefix, under 72 chars — `✨ feat:`, `🐛 fix:`, `♻️ refactor:`. One logical change per commit; add a body when the why isn't obvious.
- After a pre-commit rejection, run `git status` and re-stage before retrying — staged files can silently drop to unstaged.
- A rename plus an edit can stage as a rename-only entry (`similarity index 100%`); check `git diff --cached <path>` for real `+` / `-` lines before committing.
- Compose multi-line PR / issue / commit bodies in a file and pass `--body-file` / `-F`; an inline heredoc trips the push-protection hook's body scan.
- In a multi-PR split only the final PR says `Closes #N`; the others `Part of #N`.

## File Naming

Source files: PascalCase matching the primary type. Tests: `<SourceFileName>Tests.swift`. YAML presets: snake_case. New files under `Pastura/Pastura/` and `Pastura/PasturaTests/` are picked up by synchronized folder groups — never hand-edit `project.pbxproj`.

## Confirmation Policy

Ask before adding an SPM dependency, changing a public protocol signature, or making a design change beyond the current scope. If deferring a follow-up would leave `main` less safe between merges, bundle it rather than split.

## Decision Records

`docs/decisions/ADR-NNN.md`; read `docs/decisions/INDEX.md` before citing one. An Accepted ADR whose decisions have not shipped is edited in place; after shipping, add `§N. Amendment YYYY-MM-DD`. Factual corrections are edited in place at any age. New ADRs go through `/claude-kit:write-adr` and are added to the roster below by hand.

### ADR roster

001 Architecture Overview (Phase 1) · 002 llama.cpp interim LLM backend · 003 Background execution · 004 Multi-platform strategy · 005 Content safety architecture · 006 Cloud API implementation details · 007 DL-time demo replay (iOS lifecycle) · 008 Route identity vs render-time hints · 009 View testing strategy · 010 Localization (i18n: ja/en) · 011 6 GB RAM tier · 012 YAML strategy post-kaml · 013 Headless macOS simulation harness · 014 Release automation toolchain · 015 Execution-log retention posture · 016 Home redesign — bottom-tab IA · 017 Simulation focus mode · 018 Format-preserving visual→YAML boundary sync · 019 Raise minimum deployment target to iOS 18 · 020 Shared-scenario backward-compat · 021 Graceful degradation of LLM turn failures · 022 Phase/event extension contract · 023 KMP Engine migration architecture · 024 Scenario semantic lint layer · 025 Gallery scenario ordering · 026 LLM-dynamic Word Wolf topics (near-term no-go) · 027 Generic `pairwise_payoff` scoring logic · 028 Dark-mode token pairing (trait-resolving `PasturaDynamicColor`) · 029 Shared-scenario highlights (static curated excerpts)

| Document | Content |
|---|---|
| `docs/decisions/ADR-006.md` | Cloud API implementation details (Phase 3) — **reserved, not yet written**; a gap in the sequence, not a free slot (ADR-005 §7.5) |

Other documents: README § Documentation, `docs/ROADMAP.md`, `docs/specs/`, `docs/qa/`, `docs/ci/xcodebuild-flakes.md`, `docs/agent-tooling/`.

## Context-Specific Rules

`.claude/rules/` — a path-scoped rule loads when a matching path is read (`head -14 .claude/rules/*.md` prints each `paths:`). Read the relevant one at plan time:

- `engine.md`, `models-and-data.md`, `testing.md`, `presets.md`, `adr-writing.md`, `ci-workflows.md` — per-area conventions
- `i18n.md` / `i18n-ui.md` / `i18n-catalog.md` — localization callsites, UI traps, catalog editing
- `navigation.md` — bottom-tab IA (ADR-016); `scenario-editor.md` — dual-buffer funnel invariant
- `swiftui-traps.md`, `build-traps.md`, `uitest-traps.md`, `view-testing.md`, `swift-testing-parallelism.md` — UI, build, and test traps
- `kmp-interop.md` — K/N ↔ Swift boundary (ADR-023); `lp-content.md` — public site copy; `automation-output-contract.md` — unattended generators

Always-loaded: `swift-isolation.md` (isolation traps with no diagnostic) and `xcodebuild-cli.md` (wrapper invocation).

## Agent Tooling

`.claude/settings.json` enables the `claude-kit@claude-kit` plugin, which supplies `claude-kit:critic`, `claude-kit:implementer`, and `/claude-kit:write-adr`. Confirm the namespaced name resolves before depending on one; update with `/plugin`. Install steps: CONTRIBUTING.md § "If you use Claude Code".
