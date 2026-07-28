# Pastura — AIgazing simulator

> Read this file in full before starting any task.

> 📝 When editing this file, see "Reference Documents" first. README.md / CONTRIBUTING.md may need parallel updates.

## Current Phase

**Phase 2: Expansion — ✅ Complete (2026-07-23).** Phase 3 (Community) not yet entered — its prerequisite (an active user base) is unmet at launch, so Phase 3 features stay deferred. See `docs/ROADMAP.md` for scope.
Phase 1 MVP shipped via TestFlight (conditional Go, 2026-04-13); v1.0 released to the App Store 2026-07-23.
If a requested feature is listed under Phase 3, do not implement it — reference the roadmap and defer.

Phase 2 progress:
- **Localization (i18n: ja/en)** — *implementation complete* (ADR-010 Steps A–E merged, umbrella #276 closed). English App Store launch — the Phase 2 → Phase 3 gate — **achieved 2026-07-23** (v1.0 approved & released). Step table + PR history: `docs/ROADMAP.md` § "Localization Plan".

Phase 2 increments: see `docs/ROADMAP.md` § "Phase 2 increments (detail)".

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
  - Safety-prerequisite follow-ups are a trade-off, not a scope-hygiene choice: if deferring a follow-up leaves `main` in a less-safe state until it lands, **bundle it**. Splitting stays correct for *orthogonal* follow-ups; when unsure, surface the trade-off (extra commits vs. the between-merges risk window) rather than deciding silently.
- Major changes to public protocol signatures require user approval
- Significant design changes beyond the current scope: stop and report first

## Scope & Completeness Discipline

- **Enumerate every instance before scoping a cross-cutting change** (a bug *class* — a mechanism, not one site; or a strip / rename / add across files). List all sites (`grep` / `jq` / `find`) and scope against that list, not the one file you opened — silent siblings resurface later with misleading framing. Watch the sibling `+Feature.swift` extension: cross-check `grep` against `find <dir> -name '*.swift'`.
- **Grep the OLD shape after any bulk substitution.** A byte-exact multi-site substitution (`Edit(replace_all)`, `sed`, editor find-replace) silently skips occurrences that differ only in leading whitespace or nesting depth, and typically still reports success — grep for the old shape afterward to confirm zero residuals.

## Access Modifiers

- All protocol definitions: `public`
- All types in Models/: `public`
- Internal implementation details: `internal` (default)

## Swift Coding Conventions

- **Automated hooks** — split by gate type. Activate the git side once per clone with `./scripts/setup.sh`.
  - **Git pre-commit** (`scripts/git-hooks/pre-commit`): on `git commit`, runs `swiftlint lint --strict` + `xcodebuild build`, then a set of `scripts/*-gate.sh` sub-gates. Fail-fast; CI mirrors every check. The sub-gates are **not enumerated here** — the hook is the authoritative list, and each gate's script-header doc-comment carries its trigger paths, flags, and tool prerequisites (some need `jq` / `python3`). What matters at this altitude: each sub-gate **self-gates on its own staged inputs** and stays unconditional (CI re-runs it — defense in depth); and `swiftlint` + `xcodebuild build` are **changeset-gated** by `scripts/precommit-gate-classify.sh` (#625), conservative by inversion — skipped only when every staged path is provably build-irrelevant (`web/`, `docs/`, `.github/`, `.claude/`, …), so a docs/web-only commit skips the iOS build.
  - **Claude Code hooks** (`.claude/settings.json`): on file edit (`PostToolUse` Edit|Write), `swift-format` + `swiftlint --fix` auto-format. On `gh pr create` (`PreToolUse`), `check-claude-md-modified.sh` reminds to record a convention / trap / Phase 2 progress entry unless the branch already touched CLAUDE.md or `.claude/rules/`; it also nudges when a CLAUDE.md section the "Reference Documents" table mirrors (Architecture / Hard Rules / Dependency Rules / Tech Stack / Directory Structure / Git Conventions → README/CONTRIBUTING) changed without its mirror, via section-range overlap on `HEAD:CLAUDE.md` (the source-driven Bundled-models mirror and the i18n/ContentBlocklist mirror inside Swift Coding Conventions are out of scope). After a `/orchestrate` ready-PR create (`PostToolUse`, gated via `gated-runner.sh` to the `gh pr create --base` shape so unattended `--draft` flows are excluded), `pr-created-reflection.sh` prompts to restate the change's device-QA steps, surface session observations, and note any memory to write.
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
- **Rename PRs — verify staged *content*, not just the `R` status.** `git mv` + an `Edit` on the renamed path can leave the edit in the working tree only, staging a rename-only entry (`--stat` shows `… | 0`, `similarity index 100%`). Run `git diff --cached <path>` for real `+` / `-` lines before committing; for a delegated rename, `git add -A` from the main session rather than trusting a subagent's "staged" report.
- **Compose multi-line PR / issue / commit bodies in a file, not an inline heredoc** — write it with the Write tool, then `gh … --body-file FILE` / `git commit -F FILE`. An inline heredoc trips the quote-blind body scan of `scripts/hooks/block-force-push-and-pr-ready.sh` on any `git push --force`-shaped line, and a single-quoted one (`<<'TAG'`) also keeps `\$` / `` \` `` escapes literal.
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
│   └── ...            # additional screens (Community, Report, Settings, Splash, ModelDownload, ModelSelection)
├── Utilities/
└── Resources/
    ├── Presets/              # Bundled YAML scenarios
    ├── DemoPresets/          # Demo-backing scenarios; bundle-flattened with Presets/ but excluded from PresetLoader.presetFileNames (never in the user picker)
    ├── DemoReplays/          # DL-time demo playback (ADR-007)
    ├── ContentBlocklist.json # ADR-005 content safety
    └── *.xcstrings           # Localizable / InfoPlist string catalogs

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

```
shared/                          # KMP shared modules (#501 / ADR-023). Gradle/Kotlin Multiplatform.
├── models/                      #   Mirrors Swift Models/; landed as infra, not production-wired.
└── engine/                      #   Stage-2 gate slice landed; the bulk port and iOS consumption stay gated (Phase 3.0) — read ADR-023 §6/§12 before editing.
```

```
tools/                           # Dev tooling, outside the iOS app build
├── harness/                     #   pastura-harness — headless macOS simulation runner (ADR-013). Built by `swift build` via the root Package.swift, not by the pre-commit hook.
└── kmp-gate-spike/              #   ADR-023 Stage-2 gate spike consumer. No per-PR lane may take an XCFramework dep (ADR-023 §6, decision B′); the nightly builds the package.
```

## Agent Tooling Dependency

`.claude/settings.json` enables the `claude-kit@claude-kit` plugin, which supplies `claude-kit:critic` (mandatory `/orchestrate` Step 1b gate — it **stops** without it), the `implementer` agent, and `/claude-kit:write-adr` (the only ADR path). The installed plugin can lag the kit repo, so confirm the **namespaced** name resolves before depending on one — a bare name may resolve via a maintainer-local symlink and proves nothing. Ask which version is **active**, not what is cached: the cache keeps every version ever installed, so globbing it returns a mix in which an older version missing the skill sits beside a newer one that has it.

```bash
jq -r '.plugins["claude-kit@claude-kit"][] | "\(.version) \(.scope) \(.installPath)"' \
  ~/.claude/plugins/installed_plugins.json   # then: ls "<installPath>/skills/"
```

Update with `/plugin`. Install steps: CONTRIBUTING.md § "If you use Claude Code".

## Context-Specific Rules

`.claude/rules/` contains detailed rules with two loading modes:

**Path-scoped** (injected when a matching path is read, not from a diff / `Grep`):

- `adr-writing.md` — ADR drafting concepts: fact-claim verification at write time, mechanism contract over pinned model thresholds, inter-citation consistency, and the numbering facts `/claude-kit:write-adr` cannot derive (`docs/decisions/**`)
- `automation-output-contract.md` — Output Contract binding every unattended generator (Draft-only / never actuate, judgment→issue with counter-evidence, backpressure, conservative detection) + `gh` read-surface traps. Mirrored from claude-kit, one-way. **`paths:` fires when a skill file is read, not on a generator run** — each governed skill carries an imperative read-before-Step-0 pointer instead (`.claude/skills/**`)
- `ci-workflows.md` — CI workflow / script editing: bash 3.2 gotchas on macOS GHA runners (no `mapfile` etc.), long-lived integration-branch gating shape (`.github/workflows/**`, `scripts/**`)
- `engine.md` — Engine + LLM source (`Pastura/Pastura/Engine/**`, `Pastura/Pastura/LLM/**`)
- `i18n.md` — Localization workflow: `String(format: String(localized:))` format-string pattern, `xcstringstool` sync output (multi-arg en blocks, state=new + en-only), catalog editing traps (don't `json.dumps` round-trip) (`Pastura/Pastura/**/*.swift`, `Pastura/Pastura/Resources/Localizable.xcstrings`)
- `kmp-interop.md` — K/N↔Swift boundary traps (ADR-023 KMP Engine migration): exported classes lack Swift `Sendable` (retroactive `@unchecked` only for all-`val`, sole-declaration/module); `swift_name("Parent.Child")` misses Swift nested lookup → `object Factory` in commonMain; grep the K/N type shape at plan time (`shared/**`, `tools/kmp-gate-spike/**`)
- `lp-content.md` — Public LP content concepts: AIgazing / AI観測 genre-word zoning (Hero + Bigger picture only), em-dash / prose-colon voice rule for new copy (`web/**`)
- `models-and-data.md` — Models + Data source (`Pastura/Pastura/Models/**`, `Pastura/Pastura/Data/**`)
- `navigation.md` — bottom-tab IA (ADR-016): `TabCoordinator` owns four unmodified per-tab `AppRouter`s; programmatic navigation goes through the current tab's `router.push(_:)` / `router.pushIfOnTop(expected:next:)`, and `navigationDestination(item:|isPresented:)` is forbidden inside views pushed onto any tab's stack. Sheet-owned NavigationStacks are exempt. Path-scoped to app Swift source — every feature directory (`Views`/`App`) lives under the glob, so view-placement edits still load it. Accepted gaps: sessions that reach matching files only via Bash / `Grep` (never a `Read`) don't load it, and test files (incl. `ScreenshotTourTests.swift`, a nav-map input) fall outside — the nav-map pre-commit/CI drift gate backstops the latter (`Pastura/Pastura/**/*.swift`)
- `presets.md` — Bundled scenario YAML (`Pastura/Pastura/Resources/**`)
- `scenario-editor.md` — ScenarioEditor dual-buffer funnel invariant: visual fields and `yamlText` reconcile only via the `currentScenario()` funnel (`Pastura/Pastura/App/ScenarioEditor*`, `Pastura/Pastura/Views/Editor/**`, `Pastura/PasturaTests/App/ScenarioEditorViewModel*`)
- `swift-testing-parallelism.md` — `.serialized` is intra-suite only (cross-suite needs `swift test --no-parallel`); timing assertions compare against an in-test control, never an absolute (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `tools/**`)
- `swiftui-traps.md` — SwiftUI / Swift 6 trap catalog: toolbar-hide API matrix (iOS 17→26), footguns surfaced during app development; cross-references `navigation.md` for AppRouter mechanics (`Pastura/Pastura/**/*.swift`)
- `testing.md` — Test target (`Pastura/PasturaTests/**`)
- `uitest-traps.md` — XCUITest-only traps: structural `Tab` drops the `label:` `Image`'s a11y identifier/label per-launch (waiting never fixes it; button-label queries stay safe) (`Pastura/PasturaUITests/**`)
- `view-testing.md` — View test strategy: extract logic to unit-tests, narrow UI integration tests, no ViewInspector / snapshot (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**ViewModel.swift`). Decision record: [ADR-009](docs/decisions/ADR-009.md).

**Always-loaded** (no frontmatter `paths:` — relevant from any layer):

- `swift-isolation.md` — `nonisolated` annotation traps (protocol-ext default impls, custom witnesses, sibling-file extensions, reference-type sync methods, auto-synth conformance lookup, unannotated-ObjC-protocol conformance, MainActor-inferred closure handed to a framework callback) under default-MainActor isolation. Diagnostic fires at use site, not declaration — and the three runtime traps fire none at all — so it's always-loaded regardless of which file is being edited.
- `xcodebuild-cli.md` — xcodebuild CLI playbook (test commands, DerivedData layout, timeout/recovery for agent sessions). Always-loaded because xcodebuild gotchas surface during worktree switches and CI debugging, not only when editing test files.
- `subagent-usage.md` — Subagent invocation discipline (32K output-token cap, scope budget heuristics, Sonnet override). Always-loaded because subagent calls can originate from `/orchestrate`, slash commands, or any direct `Agent` invocation.
- `context-budget.md` — Always-loaded budget discipline: each addition must support the agent's next decision, not serve as human reference. Self-applying — additions to CLAUDE.md / agent docs / any no-`paths:` rules file route through this classifier first.
- `knowledge-layering.md` — Where knowledge belongs (memory / `CLAUDE.md` / `.claude/rules/` / `docs/**`) and how to promote memory → rules. Pairs with `context-budget.md`.

## File Naming

- Source: PascalCase matching primary type (e.g., `SpeakAllHandler.swift`)
- Tests: `<SourceFileName>Tests.swift`
- YAML presets: snake_case (e.g., `prisoners_dilemma.yaml`)
- New files under `Pastura/Pastura/` and `Pastura/PasturaTests/` are auto-included via Xcode synchronized folder groups (`PBXFileSystemSynchronizedRootGroup`) — do **not** hand-edit `Pastura.xcodeproj/project.pbxproj` to register them.

## Decision Records

Record architectural decisions in `docs/decisions/` as `ADR-NNN.md`.

**Editability window**: For recently-Accepted ADRs whose decisions have not yet shipped in code, prefer **in-place edits** when implementation planning surfaces a refinement. Use `§N. Amendment YYYY-MM-DD` sections only after the ADR's decisions have been implemented — Amendment text doubles reviewer overhead on every cross-section read. **Factual corrections are exempt** — text that became wrong about shipped behaviour is edited in place at any age, provided the decision itself is unchanged.

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
| `docs/decisions/ADR-004.md`           | Multi-platform strategy — KMP spike Accepted (Conditional GO); H5/H7 distribution-verification deferred (Status: Accepted; #220) |
| `docs/decisions/ADR-005.md`           | Content safety architecture (App Store review) |
| `docs/decisions/ADR-006.md`           | Cloud API implementation details (Phase 3; reserved — not yet written; see ADR-005 §7.5) |
| `docs/decisions/ADR-007.md`           | DL-time demo replay — iOS lifecycle (#152)  |
| `docs/decisions/ADR-008.md`           | Route identity vs render-time hints (`RouteHint<T>` pattern, #245) |
| `docs/decisions/ADR-009.md`           | View testing strategy (no ViewInspector / snapshot; #269) |
| `docs/decisions/ADR-010.md`           | Localization (i18n: ja/en) — Step C-1 design (Status: Proposed; #279) |
| `docs/decisions/ADR-011.md`           | 6 GB RAM tier — selection criteria + Phase 2 deferral; no-go for Gemma 3 1B IT (#477) |
| `docs/decisions/ADR-012.md`           | YAML strategy post-kaml — snakeyaml-engine-kmp for the shared Models layer (kaml archived; #220) |
| `docs/decisions/ADR-013.md`           | Headless macOS simulation harness — SwiftPM source reuse for the scenario factory (#515) |
| `docs/decisions/ADR-014.md`           | Release automation toolchain — fastlane + ASC API Key, local-first TestFlight-upload scope (Status: Accepted; #555) |
| `docs/decisions/ADR-015.md`           | Execution-log retention — no silent auto-delete (manual purge + advisory cap); SQLite kept iCloud-backed (DatabaseQueue ⇒ no WAL sidecars) (#547) |
| `docs/decisions/ADR-016.md`           | Home redesign — 4-tab bottom-tab IA + deep-link routing; `TabCoordinator`×4 unmodified AppRouter (Status: Accepted; #602) |
| `docs/decisions/ADR-017.md`           | Simulation focus mode — hide the tab bar during a run; Phase B opt-in cross-screen continuation (`keepRunningOnLeaveEnabled` default-off, `SuspendController` park-on-hide) (Status: Accepted; #646) |
| `docs/decisions/ADR-018.md`           | Format-preserving visual→YAML sync — surgical scalar patch via Yams `compose`+`Mark`; full-serialize fallback on structural/uncertain changes; `ScenarioYAMLPatcher` (Engine) (Status: Accepted; #725) |
| `docs/decisions/ADR-019.md`           | Raise minimum deployment target iOS 17 → iOS 18 — `ModelRegistry.minRAM` 6.5 GB gate already excludes every iOS-17 device, so it costs nothing (Status: Accepted; #834) |
| `docs/decisions/ADR-020.md`           | Shared-scenario backward-compat — two-layer gate on a monotonic `ENGINE_SCHEMA_VERSION` (capability `allCases` auto-gate + `min_engine_version` escape hatch); grey-out at index, never partial-run (Status: Accepted; baseline #965) |
| `docs/decisions/ADR-021.md`           | Graceful LLM turn-failure degradation — degrade by omission never fabrication; per-turn `TurnFailureGate`; circuit breaker after 3 consecutive skips; durable `degradedTurnCount` badge. § Amendment 2026-07-17: `validateAction` drops off-menu actions (canonicalizing normalized matches) instead of falling back to `options[0]`; new `.actionRejected` event (Status: Accepted; #992, #1151) |
| `docs/decisions/ADR-022.md`           | Phase/event extension contract — declare once in the two Models enums (no registry); every Swift projection no-default exhaustive; forced-decision CI gates for non-Swift consumers (Status: Accepted; #993) |
| `docs/decisions/ADR-023.md`           | KMP Engine migration (Phase 3.0) — run-path Engine port to `commonMain`, callback-only K/N boundaries; Stage-2 gate **verdict GO 2026-07-18 (§12)** — Stage 3 unblocked *pending* its four conditions (incl. a detector reading + re-estimate-or-dual-landing decision on #501 first); Data stays Swift/GRDB (Status: Accepted; #501) |
| `docs/decisions/ADR-024.md`           | Scenario semantic lint layer — `ScenarioSemanticLinter` (Engine) flags silent-no-op DSL traps at load time (error blocks, warning never blocks; R1–R20); `pastura-harness lint` gate. Post-v1 error rules ship warn-first, carve-out only when the predicate needs a DSL value from the same schema bump (§ Amendment 2026-07-17) (Status: Accepted; #994) |
| `docs/decisions/ADR-025.md`           | Gallery scenario ordering — client-side sort in `GalleryScenarioSearch.filter`: curator-pinned `featured` (nil last) → `added_at` desc (String compare) → `id`; New badge <14d; popularity/DL ranking deferred (telemetry backend vs offline/privacy positioning; revisit >150 items, opt-in); shuffle rejected (Status: Accepted; #1117) |
| `docs/decisions/ADR-026.md`           | LLM-dynamic Word Wolf topics — near-term No-Go; keep static `words:`. Mechanical validator misses homograph/part-of + false-positive-rejects `Pen↔Pencil`; diversity collapse (~3-5 pairs/category) → curated static list wins; category quality is per-language. Deferred `generate`-phase sketch + revisit on stronger model (ADR-002 §8.2; #906) (Status: Accepted; #906) |
| `docs/decisions/ADR-027.md`           | Generic `pairwise_payoff` scoring logic — payoff matrix moves from Swift to scenario YAML, unblocking ja `choose` options; `prisonersDilemma` kept permanently as a shim. ⚠️ ADR-022's no-default gate does **not** cover `==` predicates — grep `== .<case>` when adding to any enum it governs (Status: Accepted; #1151) |
| `docs/decisions/ADR-028.md`           | Dark-mode token pairing — `PasturaDynamicColor` resolves a light/dark pair via `UIColor(dynamicProvider:)`; 8 pairs wired (not 9 — `nightSurface` and `nightBubble` both claim `bubbleBackground`, so `nightSurface` is deferred). 59 of 67 light tokens still unpaired ⇒ `UIUserInterfaceStyle = Light` **stays**, removal gated on 5 conditions. ⚠️ `Color.*` now means "the device's appearance" for those 8 — a fixed-appearance consumer (`ImageRenderer` export) must read `PasturaPalette.<token>.color` directly (Status: Accepted; #1274) |
| `docs/decisions/INDEX.md`             | Full ADR decision summaries (one-line index above; full paragraphs there) |
| `docs/kmp-migration-status.md`        | KMP Engine migration (ADR-023 / #501) at-a-glance progress board — stage table + gate-enforced Wave B handler checklist. Progress view only; ADR-023 = design, #501 = execution detail |
| `docs/specs/pastura-mvp-spec-v0_3.md` | MVP specification                                         |
| `docs/specs/demo-replay-spec.md`      | DL-time demo replay — data format + component design (#152) |
| `docs/specs/demo-replay-ui.md`        | DL-time demo replay — visual / behaviour spec (#164)        |
| `docs/specs/demo-replay-mockup-prompt.md` | Claude Design prompt for the DL-time demo visual exploration |
| `docs/design/design-system.md`        | Cross-screen design system (tokens, philosophy, components) |
| `docs/design/demo-replay-reference.html` | DL-time demo visual reference prototype (HTML)             |
| `docs/security/release-checklist.md`  | Operator security checklist (GitHub settings, iOS pre-submission audit, recurring review) |
| `docs/models/onboarding.md`           | Model onboarding two-gate procedure (Stage-0 harness profile → `/model-eval` Mac filter → ADR-011 real-device accept → registration; intake #979) |
| `docs/models/eval-log.md`             | Model-eval 判定台帳 — 候補評価の verdict を committed に記録(judgment-only; 生スコアは gitignore の data/models/eval-digest.md; ADR-011 表が追跡する 6GB/1B級以外の候補が対象; #979 intake) |
| `docs/qa/navigation-qa.md`            | Navigation manual QA walkthroughs (numbered scenarios; extracted from `.claude/rules/navigation.md`) |
| `docs/ci/xcodebuild-flakes.md`        | CI UI-test flake catalog + hang/stall session-recovery walkthrough (extracted from `.claude/rules/xcodebuild-cli.md`) |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |
