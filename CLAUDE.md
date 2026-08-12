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
  - **Claude Code hooks** (`.claude/settings.json`): on file edit (`PostToolUse` Edit|Write), `swift-format` + `swiftlint --fix` auto-format. On `gh pr create` (`PreToolUse`), `check-claude-md-modified.sh` reminds to record a convention / trap / Phase 2 progress entry unless the branch already touched an agent-instruction file (CLAUDE.md, `.claude/rules/`, `.claude/agents/`); it also nudges when a CLAUDE.md section the "Reference Documents" table mirrors (Architecture / Hard Rules / Dependency Rules / Tech Stack / Directory Structure / Git Conventions → README/CONTRIBUTING) changed without its mirror, via section-range overlap on `HEAD:CLAUDE.md` (the source-driven Bundled-models mirror and the i18n/ContentBlocklist mirror inside Swift Coding Conventions are out of scope); and when the branch grows agent-instruction files past a tiered size threshold, it asks for a `Context-economy:` Keep/Drop record in the PR body (#1361). After a `/orchestrate` ready-PR create (`PostToolUse`, gated via `gated-runner.sh` to the `gh pr create --base` shape so unattended `--draft` flows are excluded), `pr-created-reflection.sh` prompts to restate the change's device-QA steps, surface session observations, and note any memory to write.
  - Why the split: Claude Code's hook `if` field fails-open on complex Bash, so commit-time gates living there would surface misleading errors on unrelated tool calls. Git's `pre-commit` fires only on `git commit` and is tight by construction.
  - **Opt-in, per-user — deliberately NOT wired here**: `scripts/prune-stale-worktrees.sh` removes stale auto-named worktrees left by unattended routines. Destructive, and the routines motivating it are per-machine, so wire it as a `SessionStart` hook in your own untracked `.claude/settings.local.json` — never the tracked `settings.json`. Dry-run is the default. Predicate and safety layering: the script's header.
- **Error types:** Layer-specific — `SimulationError` (Models, co-located with `SimulationEvent`),
  `LLMError` (LLM), `DataError` (Data). App layer catches and maps to UI presentation.
- **Error message i18n prep:** On `LocalizedError`-conforming types (`SimulationError`, `LLMError`, `DataError`, ...), wrap `errorDescription` literals in `String(localized: "...")`. Tests assert via `.contains(...)` partial matching, not equality. Keeps the current English-only scope while making future translation additive.
- **User-facing String literals:** Any new user-facing English `String` literal — `Text("...")`, alert / toast / `errorMessage` assignments, accessibility labels — must be wrapped in `String(localized: "...")` so it lands in `Localizable.xcstrings` and gets a `ja` translation. Three-tier enforcement: SwiftLint tripwire (edit-time), `scripts/check_i18n_potential_keys.py` audit (dev-run), `localization-coverage` CI gate. Architecture: `docs/i18n/leak-detection.md`. Workflow conventions: format strings and the Form A fallback hazard → `.claude/rules/i18n.md`; `xcstringstool` sync output and catalog editing → `.claude/rules/i18n-catalog.md`.
- **Debug builds under a suffixed bundle ID** — `app.pastura.Pastura.dev` / display name `Pastura Dev`, via `BUNDLE_ID_SUFFIX` (empty on Release), so a locally-installed dev build coexists with the App Store build. A new bundle-ID-shaped identifier must decide whether it has to **track** the suffix: one declared in `Info.plist` does (use `$(PRODUCT_BUNDLE_IDENTIFIER)` on both sides — a `BGTaskScheduler` identifier mismatch only *logs*, so it ships silently dead), a per-app-container one does not (background `URLSession`; renaming it orphans in-flight downloads). Also shifts `defaults write` domains, and OSLog filtering now matches both installed apps. See #1391 for the accepted-collision list (Universal Links, `pastura://`, duplicated model downloads).
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

**Path-scoped** (injected when a matching path is read, not from a diff / `Grep`; a rule created mid-session never injects there — `knowledge-layering.md` § "A rules file created mid-session never injects in that session"):

- `adr-writing.md` — ADR drafting concepts; the once-per-draft grep checklist lives in `docs/decisions/adr-writing-guide.md` (`docs/decisions/**`)
- `automation-output-contract.md` — Output Contract binding every unattended generator (Draft-only / never actuate, judgment→issue with counter-evidence, backpressure). Mirrored from claude-kit, one-way. **`paths:` fires when a skill file is read, not on a generator run** — each governed skill carries an imperative read-before-Step-0 pointer instead (`.claude/skills/**`)
- `build-traps.md` — filename `.stringsdata` collisions + SwiftLint directive placement around a `///` doc comment. Fires in every Swift target — the § header carries the reach (`Pastura/Pastura/**/*.swift`, `Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `tools/harness/**`)
- `ci-workflows.md` — CI workflow / script editing traps: bash 3.2 on macOS runners, required-check-safe path gating, long-lived integration-branch gating (`.github/workflows/**`, `scripts/**`)
- `engine.md` — Engine + LLM source (`Pastura/Pastura/Engine/**`, `Pastura/Pastura/LLM/**`)
- `i18n.md` — Swift-side localization conventions: Form B `String(format: String(localized:))`, the Form A runtime-fallback hazard, plurals, Tier 2 audit planning (`Pastura/Pastura/**/*.swift`, `Pastura/Pastura/Resources/Localizable.xcstrings`)
- `i18n-catalog.md` — `Localizable.xcstrings` editing + `xcstringstool` sync output. **Loads on a `Read` of the catalog, so a scripted mutation loads nothing** — read it explicitly before one (`Pastura/Pastura/Resources/Localizable.xcstrings`)
- `kmp-interop.md` — K/N↔Swift boundary traps (ADR-023); grep the K/N type shape at plan time (`shared/**`, `tools/kmp-gate-spike/**`)
- `lp-content.md` — Public LP content: genre-word zoning, voice rule for new copy (`web/**`)
- `models-and-data.md` — Models + Data source (`Pastura/Pastura/Models/**`, `Pastura/Pastura/Data/**`)
- `navigation.md` — bottom-tab IA (ADR-016): four per-tab `AppRouter`s under `TabCoordinator`; `navigationDestination(item:|isPresented:)` forbidden inside a view pushed onto a tab's stack. Its own § Scope explains why each glob entry is load-bearing — read it before editing the frontmatter (`Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**`, `Pastura/Pastura/PasturaApp.swift`)
- `presets.md` — Bundled scenario YAML (`Pastura/Pastura/Resources/**`)
- `scenario-editor.md` — ScenarioEditor dual-buffer funnel invariant: visual fields and `yamlText` reconcile only via `currentScenario()` (`Pastura/Pastura/App/ScenarioEditor*`, `Pastura/Pastura/Views/Editor/**`, `Pastura/PasturaTests/App/ScenarioEditorViewModel*`)
- `swift-testing-parallelism.md` — `.serialized` is intra-suite only; timing assertions need an in-test control (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `tools/**`)
- `swiftui-traps.md` — SwiftUI / Swift 6 trap catalog for the UI layers; cross-layer build/lint traps live in `build-traps.md` (`Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**`, `Pastura/Pastura/PasturaApp.swift`)
- `testing.md` — Test target (`Pastura/PasturaTests/**`)
- `uitest-traps.md` — XCUITest-only traps: structural `Tab` drops its `label:` a11y identifier per-launch (`Pastura/PasturaUITests/**`)
- `view-testing.md` — View test strategy: extract logic to unit tests, no ViewInspector / snapshot ([ADR-009](docs/decisions/ADR-009.md)) (`Pastura/PasturaTests/**`, `Pastura/PasturaUITests/**`, `Pastura/Pastura/Views/**`, `Pastura/Pastura/App/**ViewModel.swift`)

**Always-loaded** (no frontmatter `paths:` — relevant from any layer):

- `swift-isolation.md` — `nonisolated` annotation traps under default-MainActor isolation. Always-loaded because the diagnostic fires at the use site, not the declaration — and the silent runtime-trap patterns fire none at all.
- `xcodebuild-cli.md` — xcodebuild CLI playbook (test commands, DerivedData layout, timeout/recovery). Always-loaded because the gotchas surface during worktree switches and CI debugging, not only when editing tests.
- `subagent-usage.md` — Subagent output-cap discipline (per-model output cap, review-attention scope budget, model choice as a cost lever not a budget one). Always-loaded because subagent calls originate from any layer.
- `context-budget.md` — Content discipline for always-loaded files. Self-applying — route additions to CLAUDE.md / agent docs / any no-`paths:` rule through its classifier first.
- `knowledge-layering.md` — Which tier knowledge belongs in (memory / `CLAUDE.md` / `.claude/rules/` / `docs/**`) and how to promote memory → rules. Pairs with `context-budget.md`.

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
| `docs/decisions/INDEX.md`             | Full ADR decision summaries — the ADR lookup surface (roster below is titles only) |
| `docs/decisions/ADR-006.md`           | Cloud API implementation details (Phase 3) — **reserved, not yet written**; a gap in the sequence, not a free slot (ADR-005 §7.5). Keep as a **table row with the path in cell 1** — `consistency-audit`'s `load_reserved_adrs` parses it to suppress `dangling_adr` false positives |
| `docs/decisions/adr-writing-guide.md` | ADR inter-citation consistency checklist — run once after drafting / amending (dates, SHAs, `file:line`, period words; projection-vs-measurement and status-flip variants). Companion to `.claude/rules/adr-writing.md` §3 |
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
| `docs/qa/dark-mode-qa.md`             | Dark-appearance manual QA walkthrough (ADR-028 gates 4/5; the six risk classes no test can reach — fixed tokens, materials, fixed-appearance exports, non-SwiftUI surfaces, occlusion layers, a rendered state with no ground behind it) |
| `docs/ci/xcodebuild-flakes.md`        | CI + local UI-test flake catalog + hang/stall session-recovery walkthrough (extracted from `.claude/rules/xcodebuild-cli.md`) |
| `docs/prototype/among_them_prototype.py` | Python prototype (reference implementation) |

### ADR roster

Titles only — **read [`docs/decisions/INDEX.md`](docs/decisions/INDEX.md) before citing an ADR**; it carries the full decision summary for every entry below.

001 Architecture Overview (Phase 1) · 002 llama.cpp interim LLM backend · 003 Background execution · 004 Multi-platform strategy · 005 Content safety architecture · 006 Cloud API implementation details · 007 DL-time demo replay (iOS lifecycle) · 008 Route identity vs render-time hints · 009 View testing strategy · 010 Localization (i18n: ja/en) · 011 6 GB RAM tier · 012 YAML strategy post-kaml · 013 Headless macOS simulation harness · 014 Release automation toolchain · 015 Execution-log retention posture · 016 Home redesign — bottom-tab IA · 017 Simulation focus mode · 018 Format-preserving visual→YAML boundary sync · 019 Raise minimum deployment target to iOS 18 · 020 Shared-scenario backward-compat · 021 Graceful degradation of LLM turn failures · 022 Phase/event extension contract · 023 KMP Engine migration architecture · 024 Scenario semantic lint layer · 025 Gallery scenario ordering · 026 LLM-dynamic Word Wolf topics (near-term no-go) · 027 Generic `pairwise_payoff` scoring logic · 028 Dark-mode token pairing (trait-resolving `PasturaDynamicColor`) · 029 Shared-scenario highlights (static curated excerpts)

Titles are kept byte-identical to INDEX's `## ADR-NNN — <title>` headings. **Nothing prompts an author to append here** — add a new ADR by hand (`adr-writing.md` §4). A `/consistency-audit` run flags the omission afterwards as `adr_roster_drift` — manual and after-the-fact, not a gate. ADR-006 is reserved-unwritten — see its row above.

Two cross-cutting gotchas that fire outside their own ADR's subject area:

- ⚠️ **ADR-022's no-default gate does not cover `==` predicates** — grep `== .<case>` when adding a case to any enum it governs (ADR-027).
- ⚠️ **A fixed-appearance export (`ImageRenderer`) must inject its appearance** — `.environment(\.colorScheme, …)` plus an explicit parameter; omitting it, not reading a paired alias, is what renders light on a dark device. Read `PasturaPalette.<token>.color` too, so `light` and `dark` stay distinct (ADR-028 § Amendment 2026-08-06).
