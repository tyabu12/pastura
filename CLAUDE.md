# Pastura — AIgazing simulator

> Read this file in full before starting any task.

> 📝 When editing this file, see "Reference Documents" first. README.md / CONTRIBUTING.md may need parallel updates.

## Current Phase

**Phase 2: Expansion** — See `docs/ROADMAP.md` for scope.
Phase 1 MVP shipped via TestFlight (conditional Go, 2026-04-13).
If a requested feature is listed under Phase 3, do not implement it — reference the roadmap and defer.

Phase 2 progress:
- **Localization (i18n: ja/en)** — *in progress* — App Store launch surface. Step table + PR history: `docs/ROADMAP.md` § "Localization Plan" (#276/#277).

Phase 2 increments (implementation detail → `docs/ROADMAP.md` § "Phase 2 increments (detail)"): Visual Scenario Editor (#83) · Background execution (#84) · Shared Scenarios (#87/#93) · Simulation result export (#91/#98) · Inference speed display (#99) · Past-results code-phase events (#102/#113) · Launch animation (#412/#415) · Home redesign — bottom-tab IA (ADR-016, #602) · Viewer prediction (#906/#915) · Reflect phase + log window (#906/#907) · Contradiction badge (#906/#916) · Relationship update phase (#906/#910) · Shared-scenario compat gate (ADR-020 baseline, #965).

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

- **Automated hooks** — split by gate type. Activate the git side once per clone with `./scripts/setup.sh`.
  - **Git pre-commit** (`scripts/git-hooks/pre-commit`): on `git commit`, runs `swiftlint lint --strict`, `xcodebuild build`, `bash scripts/blocklist-precommit-gate.sh` (also surfaces `bash scripts/build-blocklist.sh --check` indirectly when the staged diff touches `docs/blocklist/source.json` or `Pastura/Pastura/Resources/ContentBlocklist.json` — requires `brew install jq`), `bash scripts/gallery-precommit-gate.sh`, and `bash scripts/navigation-map-precommit-gate.sh` (runs `python3 scripts/generate-navigation-map.py --self-test`/`--check` when the staged diff touches a nav-map input — `Pastura/Pastura/{Views,App}/**`, `ScreenshotTourTests.swift`, the generator, or the generated map; requires `python3` from the Xcode Command Line Tools), and `bash scripts/scenario-editor-funnel-gate.sh` (counts `buildScenario()` in `ScenarioEditorViewModel*.swift`; `!= 3` fails — the #338 funnel tripwire, self-gates on the VM glob). Fail-fast. CI mirrors the same checks. `swiftlint` + `xcodebuild build` are gated on the staged changeset (`scripts/precommit-gate-classify.sh`, #625): conservative by inversion — they are skipped only when every staged path is provably build-irrelevant (`web/`, `docs/`, `.github/`, `.claude/`, …), so a docs/web-only commit skips the iOS build. The blocklist/gallery/p8/navigation-map/scenario-editor-funnel sub-gates self-gate on their own inputs and stay unconditional.
  - **Claude Code hooks** (`.claude/settings.json`): on file edit (`PostToolUse` Edit|Write), `swift-format` + `swiftlint --fix` auto-format. On `gh pr create` (`PreToolUse`), a reminder checks whether the branch has touched this file's "Phase 2 progress" — useful when migrating Phase 2 entries.
  - Why the split: Claude Code's hook `if` field fails-open on complex Bash, so commit-time gates living there would surface misleading errors on unrelated tool calls. Git's `pre-commit` fires only on `git commit` and is tight by construction.
- **Error types:** Layer-specific — `SimulationError` (Models, co-located with `SimulationEvent`),
  `LLMError` (LLM), `DataError` (Data). App layer catches and maps to UI presentation.
- **Error message i18n prep:** On `LocalizedError`-conforming types (`SimulationError`, `LLMError`, `DataError`, ...), wrap `errorDescription` literals in `String(localized: "...")`. Tests assert via `.contains(...)` partial matching, not equality. Keeps the current English-only scope while making future translation additive.
- **User-facing String literals:** Any new user-facing English `String` literal — `Text("...")`, alert / toast / `errorMessage` assignments, accessibility labels — must be wrapped in `String(localized: "...")` so it lands in `Localizable.xcstrings` and gets a `ja` translation. Three-tier enforcement: SwiftLint tripwire (edit-time), `scripts/check_i18n_potential_keys.py` audit (dev-run), `localization-coverage` CI gate. Architecture: `docs/i18n/leak-detection.md`. Workflow conventions (format strings, `xcstringstool` sync output, catalog editing): `.claude/rules/i18n.md`.
- **Logger privacy:** OSLog redacts `String` / `Substring` / `Error` interpolations as `<private>` in TestFlight / Release. Annotate non-`.debug` Logger interpolations with `privacy: .public`. Don't Logger-interpolate user content (scenario text, agent outputs) — route through `TurnRecord` persistence. Narrow exceptions for already-persisted diagnostics and public-API parameters are documented as inline comments at `LLMCaller.logParseFailure` and `BackgroundSimulationManager.scheduleRequest`.
- **Swift 6 Concurrency:** `Sendable` for cross-actor types, `@MainActor` for UI state,
  `AsyncStream` over callbacks. Engine/LLM work runs on non-main actors or default executor.
- **Default Actor Isolation:** Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  All types in `Models/`, `LLM/`, `Engine/`, and `Data/` **MUST** be marked `nonisolated` at the
  type level to avoid unnecessary MainActor binding.
  `Views/` and `App/` use the default (MainActor).
  Specific isolation traps (protocol-ext default impls building escaping closures,
  custom-witness value types, sibling-file extensions, reference-type sync methods,
  auto-synth Equatable/Hashable conformance lookup from nonisolated callers) —
  see `.claude/rules/swift-isolation.md`.
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
| Min iOS            | 18.0                          |           |
| YAML parser        | Yams                          | 6.2.2     |
| SQLite             | GRDB                          | 7.11.1    |
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

The `/release` skill's release **tag** push (via `scripts/release.sh`, ADR-014)
is also exempt: a tag ref is not branch-protected, edits no tracked files, and
is gated behind the skill's mandatory confirmation. Any *code* change a release
needs (a `MARKETING_VERSION` bump) still goes through `/orchestrate`.

### TDD Approach

Engine and LLM layer: test-first (write failing test → minimal implementation → refactor).
Data and UI layers: implement first, add tests for non-trivial logic.

Implementation order: `Models → LLM → Engine → Data → Views → App → Integration test`

### Git Conventions

- **Branch:** `feature/<description>`, `fix/<description>`, `docs/<description>`
- **Branch ops:** Prefer `git switch <branch>` / `git switch -c <branch>` over `git checkout`.
  Never use `git switch` with `--discard-changes`, `--force`, `-f`, or `-C` — they discard
  uncommitted work or overwrite branch refs.
- **Commits:** Conventional Commits with emoji prefix, under 72 chars.
  `✨ feat:`, `🐛 fix:`, `♻️ refactor:` — add body when "why" isn't obvious.
- **Small and focused** — one logical change per commit.
- **Re-stage after a pre-commit hook rejection.** When the pre-commit hook (`swiftlint --strict`, `xcodebuild build`, …) rejects a commit, do not assume the previously-staged files survived — they can silently drop to "Changes not staged". Run `git status` and re-stage (`git add -u` or explicit paths) **before** retrying, or the retry commits a partial changeset and splits one logical change across two commits.
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

web/                             # The pastura.app site (Astro SSG, deployed via .github/workflows/deploy-pages.yml; #475)
├── astro.config.mjs             # i18n (en root / ja prefix), sitemap, trailingSlash
├── public/                      # Static assets served at site root (css/, js/, img/, CNAME, robots.txt, .nojekyll)
└── src/
    ├── layouts/BaseLayout.astro # Shared <head> + <body> shell (computes canonical/hreflang/og per locale)
    └── pages/                   # Route files → en at root, ja mirror under ja/
        ├── index.astro          #   /            (LP; ja/index.astro → /ja/)
        ├── support.astro        #   /support/    (ASC Support URL)
        └── legal/privacy-policy.astro  # /legal/privacy-policy/ (App Store privacy policy URL)
```

## Context-Specific Rules

`.claude/rules/` contains detailed rules with two loading modes:

**Path-scoped** (loaded only when editing matching files):

- `adr-writing.md` — ADR drafting concepts: fact-claim verification at write time, mechanism contract over pinned model thresholds (`docs/decisions/**`)
- `ci-workflows.md` — CI workflow / script editing: bash 3.2 gotchas on macOS GHA runners (no `mapfile` etc.), long-lived integration-branch gating shape (`.github/workflows/**`, `scripts/**`)
- `engine.md` — Engine + LLM source (`Pastura/Pastura/Engine/**`, `Pastura/Pastura/LLM/**`)
- `i18n.md` — Localization workflow: `String(format: String(localized:))` format-string pattern, `xcstringstool` sync output (multi-arg en blocks, state=new + en-only), catalog editing traps (don't `json.dumps` round-trip) (`Pastura/Pastura/**/*.swift`, `Pastura/Pastura/Resources/Localizable.xcstrings`)
- `lp-content.md` — Public LP content concepts: AIgazing / AI観測 genre-word zoning (Hero + Bigger picture only), em-dash / prose-colon voice rule for new copy (`web/**`)
- `models-and-data.md` — Models + Data source (`Pastura/Pastura/Models/**`, `Pastura/Pastura/Data/**`)
- `navigation.md` — bottom-tab IA (ADR-016): `TabCoordinator` owns four unmodified per-tab `AppRouter`s; programmatic navigation goes through the current tab's `router.push(_:)` / `router.pushIfOnTop(expected:next:)`, and `navigationDestination(item:|isPresented:)` is forbidden inside views pushed onto any tab's stack. Sheet-owned NavigationStacks are exempt. Path-scoped to app Swift source — every feature directory (`Views`/`App`) lives under the glob, so view-placement edits still load it. Accepted gaps: planning-before-edit sessions no longer preload it, and test files (incl. `ScreenshotTourTests.swift`, a nav-map input) fall outside — the nav-map pre-commit/CI drift gate backstops the latter (`Pastura/Pastura/**/*.swift`)
- `presets.md` — Bundled scenario YAML (`Pastura/Pastura/Resources/**`)
- `scenario-editor.md` — ScenarioEditor dual-buffer funnel invariant: visual fields and `yamlText` reconcile only via the `currentScenario()` funnel (`Pastura/Pastura/App/ScenarioEditor*`, `Pastura/Pastura/Views/Editor/**`, `Pastura/PasturaTests/App/ScenarioEditorViewModel*`)
- `swiftui-traps.md` — SwiftUI / Swift 6 trap catalog: toolbar-hide API matrix (iOS 17→26), footguns surfaced during app development; cross-references `navigation.md` for AppRouter mechanics (`Pastura/Pastura/**/*.swift`)
- `testing.md` — Test target (`Pastura/PasturaTests/**`)
- `view-testing.md` — View test strategy: extract logic to unit-tests, narrow UI integration tests, no ViewInspector / snapshot (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**ViewModel.swift`). Decision record: [ADR-009](docs/decisions/ADR-009.md).

**Always-loaded** (no frontmatter `paths:` — relevant from any layer):

- `swift-isolation.md` — `nonisolated` annotation traps (protocol-ext default impls, custom witnesses, sibling-file extensions, reference-type sync methods, auto-synth conformance lookup) under default-MainActor isolation. Diagnostic fires at use site, not declaration — always-loaded so it's visible regardless of which file is being edited.
- `xcodebuild-cli.md` — xcodebuild CLI playbook (test commands, DerivedData layout, timeout/recovery for agent sessions). Always-loaded because xcodebuild gotchas surface during worktree switches and CI debugging, not only when editing test files.
- `subagent-usage.md` — Subagent invocation discipline (32K output-token cap, scope budget heuristics, Sonnet override). Always-loaded because subagent calls can originate from `/orchestrate`, slash commands, or any direct `Agent` invocation.
- `context-budget.md` — Always-loaded budget discipline: each addition must support the agent's next decision, not serve as human reference. Self-applying — additions to CLAUDE.md / agent docs / any no-`paths:` rules file route through this classifier first.
- `knowledge-layering.md` — Where knowledge belongs (memory / `CLAUDE.md` / `.claude/rules/` / `docs/**`) and how to promote memory → rules. Pairs with `context-budget.md`.

## File Naming

- Source: PascalCase matching primary type (e.g., `SpeakAllHandler.swift`)
- Tests: `<SourceFileName>Tests.swift`
- YAML presets: snake_case (e.g., `prisoners_dilemma.yaml`)

## Decision Records

Record architectural decisions in `docs/decisions/` as `ADR-NNN.md`.

**Editability window**: For recently-Accepted ADRs whose decisions have not yet shipped in code, prefer **in-place edits** when implementation planning surfaces a refinement. Use `§N. Amendment YYYY-MM-DD` sections only after the ADR's decisions have been implemented — Amendment text doubles reviewer overhead on every cross-section read.

## Reference Documents

`README.md` and `CONTRIBUTING.md` at the project root are public-facing
mirrors of parts of this document. When updating one of the following in
this document (or in source), check whether the public docs need the
same change:

- Architecture / Hard Rules / Dependency Rules → README "Architecture",
  CONTRIBUTING "Design principles" (anchor links)
- Tech Stack versions and platform (Swift, iOS minimum, Yams, GRDB) → README "Tech stack"
- Bundled models (`ModelRegistry.swift`) → README "Supported LLM models"
- Git Conventions → CONTRIBUTING "Workflow" / "Commits"
- Directory Structure → README "Project layout"
- i18n workflow / ContentBlocklist procedure → CONTRIBUTING "Before
  your first PR"

| Document                              | Content                                                                       |
|---------------------------------------|-------------------------------------------------------------------------------|
| `README.md`                           | Public-facing developer intro (Architecture, Tech stack, Project layout, Supported models) |
| `CONTRIBUTING.md`                     | Public-facing contributor workflow with links into CLAUDE.md anchors          |
| `docs/ROADMAP.md`                     | Phase scope, Go/No-Go criteria              |
| `docs/decisions/ADR-001.md`           | Phase 1 architecture decisions (12 ADRs)    |
| `docs/decisions/ADR-002.md`           | llama.cpp interim LLM backend decision      |
| `docs/decisions/ADR-003.md`           | BG execution (iOS 26 BGContinuedProcessingTask) |
| `docs/decisions/ADR-004.md`           | Multi-platform strategy — Accepted (Conditional GO) on #220 KMP spike; §9 GO/NO-GO synthesis (H5/H7 distribution-verification deferred) |
| `docs/decisions/ADR-005.md`           | Content safety architecture (App Store review) |
| `docs/decisions/ADR-006.md`           | Cloud API implementation details (Phase 3; reserved — not yet written; see ADR-005 §7.5) |
| `docs/decisions/ADR-007.md`           | DL-time demo replay — iOS lifecycle (#152)  |
| `docs/decisions/ADR-008.md`           | Route identity vs render-time hints (`RouteHint<T>` pattern, #245) |
| `docs/decisions/ADR-009.md`           | View testing strategy (no ViewInspector / snapshot; #269) |
| `docs/decisions/ADR-010.md`           | Localization (i18n: ja/en) — ADR body for Step C-1 design (Status: Proposed; stub #279, body #367) |
| `docs/decisions/ADR-011.md`           | 6 GB RAM tier — selection criteria + Phase 2 deferral (no-go for Gemma 3 1B IT; mechanism-contract prerequisites for future candidates; #477 / PR #480 / #483) |
| `docs/decisions/ADR-012.md`           | YAML strategy post-kaml — snakeyaml-engine-kmp adoption for the shared Models layer (kaml archived; #220 D3 / T9; ADR-008 number drift) |
| `docs/decisions/ADR-013.md`           | Headless macOS simulation harness — SwiftPM source reuse for the scenario factory (#515, impl #517) |
| `docs/decisions/ADR-014.md`           | Release automation toolchain — fastlane + ASC API Key, local-first, TestFlight-upload scope (Status: Accepted; #555) |
| `docs/decisions/ADR-015.md`           | Execution-log retention posture (no silent auto-delete; manual purge + advisory cap) + SQLite iCloud-backup decision (keep backed up; DatabaseQueue ⇒ no WAL sidecars) (#547) |
| `docs/decisions/ADR-016.md`           | Home redesign — bottom-tab IA + deep-link tab routing (4-tab; `TabCoordinator`×4 unmodified AppRouter; `.settings`/`.sharedScenarios` removed from Route; `isSimulationOnTop` = any-tab) (Status: Accepted; #602; § Amendment 2026-06-18 re-anchors the fold on hosting + scenePhase per ADR-017; § Amendment 2026-06-20 adopts iOS 18+ structural `Tab` API — search-role morph deferred (grouped search tab; detached search-role capsule reads as in-screen search), icon-only via label-closure with device-QA-contingent label fallback, #693) |
| `docs/decisions/ADR-017.md`           | Simulation focus mode — hide the tab bar during a run so tab-switching mid-run is impossible (#646 Phase A); § Amendment 2026-06-20 implements Phase B — opt-in cross-screen continuation via Variant 3 (ownership lift + `SuspendController` park-on-hide; progress suspended while away), `keepRunningOnLeaveEnabled` default-off, in-flight indicator on `RootTabView` overlay; iPad multi-window concurrent runs out of scope (Status: Accepted; #646/#682) |
| `docs/decisions/ADR-018.md`           | Format-preserving visual→YAML boundary sync — surgical scalar patch via Yams `compose`+`Mark` (value-only updates preserve comments/key order; structural & block-scalar changes + any uncertainty fall back to full serialize; reparse safety-net; `ScenarioYAMLPatcher` in Engine; supersedes #338's single-source-of-truth direction) (Status: Accepted; #725) |
| `docs/decisions/ADR-019.md`           | Raise minimum deployment target from iOS 17 to iOS 18 — the `ModelRegistry.minRAM` 6.5 GB gate already excludes every iOS-17-bound device, so the raise costs nothing while removing `#available` branches (iOS-17 `RootTabView` fallback, `ScrollPosition.scrollTo(edge:)` for #830) (Status: Accepted; #834) |
| `docs/decisions/ADR-020.md`           | Shared-scenario backward-compat across engine breaking changes — two-layer hybrid gate on a monotonic `ENGINE_SCHEMA_VERSION`: capability-derived `phases`⊄`PhaseType.allCases` auto-gate (flatten conditional sub-phases; CI-pinned) + declared `min_engine_version` escape hatch (tooling-computed floor, author-raisable for semantics); grey-out at index-display time; never partial-run; parse-throw safety net w/ update-guidance message; bump policy on semantic equivalence not syntactic additivity; envelope `version` repurposed for structural reshapes only; imports out-of-scope; land baseline before first release (Status: Accepted; baseline shipped #965 — D1/D2/D2a/D2b/D3-field/D4/D5; D3a derived-floor extractor + D7 + App Store deep-link deferred to first post-baseline PR, see ADR §7; #946) |
| `docs/specs/pastura-mvp-spec-v0_3.md` | MVP specification                                         |
| `docs/specs/demo-replay-spec.md`      | DL-time demo replay — data format + component design (#152) |
| `docs/specs/demo-replay-ui.md`        | DL-time demo replay — visual / behaviour spec (#164)        |
| `docs/specs/demo-replay-mockup-prompt.md` | Claude Design prompt for the DL-time demo visual exploration |
| `docs/design/design-system.md`        | Cross-screen design system (tokens, philosophy, components) |
| `docs/design/demo-replay-reference.html` | DL-time demo visual reference prototype (HTML)             |
| `docs/security/release-checklist.md`  | Operator security checklist (GitHub settings, iOS pre-submission audit, recurring review) |
| `docs/models/onboarding.md`           | Model onboarding two-gate procedure (Stage-0 harness profile → `/model-eval` Mac filter → ADR-011 real-device accept → registration; intake #979) |
| `docs/qa/navigation-qa.md`            | Navigation manual QA walkthroughs (scenarios 1–17; extracted from `.claude/rules/navigation.md`) |
| `docs/ci/xcodebuild-flakes.md`        | CI UI-test flake catalog + hang/stall session-recovery walkthrough (extracted from `.claude/rules/xcodebuild-cli.md`) |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |
