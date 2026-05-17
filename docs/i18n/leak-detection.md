# i18n Leak Detection

Architecture for catching English `String` literals that should be wrapped
in `String(localized:)` but aren't. Three independent tiers, each closing
a different gap. Issue [#292](https://github.com/tyabu12/pastura/issues/292)
tracks the design.

## Why three tiers

The "is this user-facing?" decision is *semantic*, not syntactic — a
single tool cannot reliably decide whether `errorMessage = "Foo"` ships
to users while `Logger.debug("Foo")` does not. We instead compose three
narrow tools whose blind spots cover each other:

| Tier | Catches | Mechanism | Cost of false positive |
|------|---------|-----------|------------------------|
| **1** Tripwire | Direct assignment to known view-model error/validation properties | SwiftLint custom rule, fires at edit time | Zero (regex is empirically calibrated) |
| **2** Audit | Indirect display paths (helper returns, computed properties, `Text(varName)`) | `xcstringstool extract --all-potential-swift-keys` + noise filters, dev-run | Reviewer time during triage |
| **3** Coverage | Already-wrapped keys without `ja` translations | JSON validator over `Localizable.xcstrings`, CI gate | Block merge until translated |

Tier 1 and Tier 2 detect *wrap leaks* (English literal not yet routed
through `String(localized:)`). Tier 3 detects *translation leaks* (key
routed but `ja` value empty/stale). They are not substitutes.

## Tier 1 — SwiftLint custom rule

**Where**: `.swiftlint.yml` § `unwrapped_user_facing_string`
**Severity**: warning (intentionally not error — see Extension below)
**Runs**: every `git commit` via the project's pre-commit hook, plus
`scripts/xcodebuild.sh build` / `test`.

The rule fires on the regex shape

```
(errorMessage|validationErrors|alertMessage|toastMessage|nameError
 |descriptionError|conditionError|promptError|outcomeAlert|deepLinkError
 |loadError)
\s*(?:=|\+=)\s*\[?\s*"[^"]+"
```

against any file under `Pastura/Pastura/`. The 11 property names are an
**empirical** list, drawn from the PR #288 audit, the four
`SimulationViewModel*.swift` wraps fixed in PR #299, and the
`SimulationView.loadError` Tier 2 leak surfaced in #311. The narrow
scope is the entire point: widening to all `String` assignments
re-introduces the noise floor that PR #288's analysis was unable to
cut through.

### What it cannot catch (by design)

- New view-model properties that haven't been added to the regex
- Helper functions returning `String` displayed via `Text(_:)`:
  ```swift
  // PhaseEditorSheet.swift (PR #288 d446fd9 — 10 unwrapped sites)
  private var phaseTypeDescription: String {
    switch phase.type {
    case .speakAll: return "All agents speak simultaneously"  // unwrapped
    ...
    }
  }
  Text(phaseTypeDescription)  // verbatim-String overload, no auto-extraction
  ```
- Direct `Text("...")` literals (these are already auto-extracted by Xcode
  IDE, but only when Xcode runs — not under our pre-commit hook)
- **Function-arg-with-literal call shapes** — e.g.
  `pauseSimulation(reason: "Background time exceeded — tap resume to continue.")`
  where the literal is passed as a keyword argument rather than assigned
  to a known view-model property. The shape varies by callee name
  (`pauseSimulation(reason:)`, `cancelSimulation(caller:)`, hypothetical
  `showAlert(message:)`, etc.) and a regex covering them would either
  enumerate every method name (maintenance burden) or widen to
  `\(\w+:\s*"…"` (re-introduces the noise floor PR #288 was unable to
  cut through). This is a design statement, not a deferred extension:
  function-arg shapes belong to Tier 2's audit script, which catches
  them at developer-run.

These gaps belong to Tier 2.

### Extension protocol

When a new `@Observable` ViewModel lands a user-facing `String?` property,
**append the property name to the regex alternation**. Re-run
`swiftlint lint --strict` against the worktree; if the strict run is
clean, the addition is safe.

The list is supposed to grow. Treat it as living documentation of the
project's empirical leak shapes, not a fixed contract.

## Tier 2 — `xcstringstool` audit

**Where**: `scripts/check_i18n_potential_keys.py`
**Runs**: developer-invoked, `python3 scripts/check_i18n_potential_keys.py`
**CI integration**: intentionally absent — see *CI gating* below.

Internally:

1. Globs `Pastura/Pastura/**/*.swift`, excluding `Engine/` (ADR-010 §4 —
   Engine reads `scenario.language` directly, not `Bundle.main`) and
   `+Previews.swift` (preview-macro bodies, dev-only).
2. Invokes `xcrun xcstringstool extract --modern-localizable-strings
   --all-potential-swift-keys`. Apple's parser splits keys into
   `Localizable` (already-wrapped, dropped) and `__PotentialKeys`
   (everything else).
3. Applies six purely syntactic noise filters:

   | Filter | Drops |
   |--------|-------|
   | `empty` | `""`, `"   "` (whitespace only) |
   | `identifier` | Short lowercase token (≤ 8 chars) — `string`, `arg`, `id` |
   | `dot-notation` | `minus.circle.fill`, `home.scenario.row` (SF Symbol or accessibility id) |
   | `url-or-path` | `https://…`, `/Users/…`, `~/Library` (decorative `~%lld` / `~5 items` intentionally kept — PR #416 / #419) |
   | `format-only` | `%arg`, `%@`, `%d` (no surrounding text) |
   | `no-letter` | Punctuation/digits only — `: `, `12-34-56`. Unicode-aware: CJK / Cyrillic / Greek strings keep their letters and pass through. |

4. Prints surviving candidates as `relpath:line:col  'key'`.

Empirically the filters drop ~42% of raw extractions on the current
codebase (1108 → 647 candidates). The reviewer is expected to triage
the remainder against the actual call site to decide *intentional
design-pending copy* (see § "Explicitly-deferred items" below), *internal
log strings* (Logger `%public` interpolations), or *real wrap leaks*
(e.g. `SimulationView.swift:535 loadError = "Scenario not found"`).

### Explicitly-deferred or permanent carve-outs

Audit candidates that are **knowingly** un-wrapped. Two flavours:

- **Deferred** — pending a downstream gating event (design copy pass,
  schema migration, etc.). Wrap when the gating event lands.
- **Permanent** — structurally machine-stable tokens (Markdown
  structure, version markers, format-string internals, user-authored
  content rendered verbatim). External-tool stability or schema
  contract outweighs locale display.

Both keep surfacing in `check_i18n_potential_keys.py` output —
recognize them as documented carve-outs rather than wrap leaks.

| Item | Source location | Gating event / Status |
|------|-----------------|-----------------------|
| `slotCopy(_:)` 3 marketing strings | `Pastura/Pastura/Views/ModelDownload/PromoCard+Helpers.swift` | **Deferred** — `docs/design/design-system.md` §7 copy pass (spec §2 decision 13) |
| `Character.accessibilityLabel` 4 cases (`Alice`/`Bob`/`Carol`/`Dave`) | `Pastura/Pastura/Views/Components/SheepAvatar.swift` | **Deferred** — Preview-only after #340 bucket-3 PR — runtime application carries `.accessibilityHidden(true)` because the names are color-slot identifiers (allocated by `forAgent(position:)`), not agent display names. Re-evaluate only if a future design binds avatars to real translated identities. |
| `ResultMarkdownExporter` machine-stable tokens (~10 candidates) | `Pastura/Pastura/App/ResultMarkdownExporter.swift` | **Permanent** — Markdown structural tokens (`<!-- pastura-export v1 -->` version marker, table data rows, separator rows like `\|-------\|-------\|--------\|`), universal joiners (`%@: %@` score pair, `%@ → %@` vote arrow, `%@=%@` field dump), Apple OS-version normalize internals (`Version `, `iOS `, `(Build `, `(build ` — matchers for Apple's raw string format), filename / timestamp / locale-identifier internals (`%@_%@.md`, `yyyyMMdd-HHmmss`, `en_US_POSIX`), YAML scenario block (user-authored verbatim). External-tool stability over locale display per #340 slice-4 decision (PR for `App/ResultMarkdownExporter` i18n wraps). |
| `YAMLReplayExporter` wire-format tokens (~80 candidates) | `Pastura/Pastura/App/YAMLReplayExporter.swift` | **Permanent** — YAML schema tokens per `docs/specs/demo-replay-spec.md` §3.2 (`schema_version`, `preset_ref`, `metadata`, `turns`, `code_phase_events`, `payload`, `kind: …` discriminators, field labels like `title:` / `recorded_at:` / `recorded_with_model:`), YAML reserved scalars (`True` / `False` / `Null` / `Yes` / `No` / `On` / `Off` and their `TRUE` / `FALSE` / … variants), escape sequences (`\n`, `\r`, `\t`, `\x%02X`), date / file-format internals (`yyyyMMdd-HHmmss`, `en_US_POSIX`, `%@_replay_%@.yaml`), version-marker comment (`# Generated by Pastura — demo-replay-spec §3.2`). Schema contract + round-trip with `YAMLReplaySource` over locale display per #340 slice-5 decision. |
| `YAMLReplaySource` error-payload + wire-format internals (~18 candidates) | `Pastura/Pastura/App/YAMLReplaySource.swift` | **Permanent** — `YAMLReplaySourceError: Error, Equatable` (NOT `LocalizedError`) error-description payloads (`Top-level is not a mapping.`, `Input is not valid UTF-8.`, `expected: string-keyed mapping`, `expected: string-keyed integer mapping`), YAML wire-format field names (`schema_version`, `code_phase_events`, `phase_type`, `phase_index`, `vote_count`, payload `kind` discriminators `elimination` / `scoreUpdate` / `voteResults` / `pairingResult` / `assignment` / `eventInjected`). Never user-surfaced — consumed only by `BundledDemoReplaySource`'s `logger.notice/debug` calls per spec §3.5 silent-skip policy. |
| `BundledDemoReplaySource` Logger interpolations (~13 candidates) | `Pastura/Pastura/App/BundledDemoReplaySource.swift` | **Permanent** — all `logger.notice` / `logger.debug` interpolations carry `privacy: .public` annotation per CLAUDE.md Logger-privacy rule, plus `os.Logger` subsystem / category strings (`com.tyabu12.Pastura`, `BundledDemoReplaySource`), preset-ref field names (`preset_ref`, `yaml_sha256`), filename suffix (`_demo`). Diagnostic-only, never user-facing UI strings. |
| `InferenceStatsFormatter` universal display units (4 candidates) | `Pastura/Pastura/Views/Simulation/InferenceStatsFormatter.swift` | **Permanent** — Technical unit tokens (`tok/s` tokens-per-second rate, `s` seconds-duration suffix; scientific / SI-derived units used as-is across locales in ML / inference contexts) and typographic display glyphs (`—` U+2014 em-dash nil-fallback marker, `•` U+2022 bullet metric joiner). Canonical convention statement lives in the enum doc-comment at the source file; `Pastura/Pastura/Views/Components/GameHeader.swift` `formatTokensPerSecond` cites it. `InferenceStatsFormatterTests` literal-pins `"12.5 tok/s • 1.5s"` as the regression guard against accidental wrap. Per #340 slice-6 decision. |
| `App/SimulationViewModel` suite Logger interpolations + BG identifiers (50 candidates) | `Pastura/Pastura/App/SimulationViewModel.swift`, `Pastura/Pastura/App/SimulationViewModel+Background.swift`, `Pastura/Pastura/App/BackgroundSimulationManager.swift` | **Permanent** — ~43 `os.Logger` `info` / `notice` / `error` interpolations annotated `privacy: .public` per CLAUDE.md Logger-privacy rule (lifecycle / scenePhase / BG-task diagnostics like `"scenePhase=.active enter: isRunning=%arg, ..."`, `"BG task activation: isRunning=%arg, ..."`, `"committed agent=%arg totalAttempts=%arg"`); 5 Logger subsystem / category strings (`com.tyabu12.Pastura` × 2 + `SimulationVM`, `StreamingDiag`, `BGSimManager`); 1 BGTaskScheduler identifier (`com.tyabu12.Pastura.simulation-continuation` per iOS 26 BGContinuedProcessingTask spec); 2 `cancelSimulation(caller:)` debug tags (`switchToCPUInference-error`, `switchToGPUInference-error`). Diagnostic-only, never user-facing UI strings. Per #340 slice-7 decision. |
| `ModelRegistry` product/vendor + wire-format + diagnostic strings (19 candidates) | `Pastura/Pastura/App/ModelRegistry.swift` | **Permanent** — Four sub-classes: (a) Product proper nouns — `displayName` (`"Gemma 4 E2B (Q4_K_M)"`, `"Qwen 3 4B (Q4_K_M)"`), `shortDisplayName` (`"Gemma 4 E2B"`, `"Qwen 3 4B"`). Trademarked / official model names; App Store + package-manager convention is to NOT translate. The user-facing human-readable copy lives in `tagline` and IS wrapped via `String(localized:)` at L40 + L71. (b) Vendor proper nouns — `vendor` (`"Google"`, `"Alibaba"`). Company names treated identically to product names. (c) Wire-format identifiers — `id` (`"gemma-4-e2b-q4-k-m"`, `"qwen-3-4b-q4-k-m"`), `fileName` (`"gemma-4-E2B-it-Q4_K_M.gguf"`, `"Qwen3-4B-Q4_K_M.gguf"`), `sha256` hex digests (64 chars each), `stopSequence` chat-template tokens (`"<\|im_end\|>"`), `assistantPrefix` thinking-mode prefill (`"<think>\n\n</think>\n\n"`), `systemPromptSuffix` model directives (`"/no_think"`). (d) Dev-only precondition diagnostic strings — `preconditionFailure("Malformed URL literal: ...")` at L7, `findCollisions` `"Duplicate id \"...\" at indices ... and ..."` / `"Duplicate fileName \"...\" at indices ... and ..."` / `"ModelRegistry catalog collisions: ..."`. Fire only on programmer error in catalog construction; never reach end user. Per #340 slice-8 decision. |
| `ModelDownloader` Logger + identifier strings (14 candidates) | `Pastura/Pastura/App/ModelDownloader.swift` | **Permanent** — Same shape as the `BundledDemoReplaySource` carve-out above. Four sub-classes: (a) `os.Logger` subsystem / category strings — `"com.tyabu12.Pastura"`, `"ModelDownloader"`. (b) Background URLSession identifier — `"com.tyabu12.Pastura.modelDownload"`. Apple's `.background(withIdentifier:)` per-identifier uniqueness constraint binds the string literal. (c) HTTP wire tokens — `"Range"` header name, `"bytes=\(resumeOffset)-"` interpolated value (audit reports the xcstringstool-substituted form `bytes=%arg-`). (d) Logger format strings carrying `privacy: .public` interpolations on diagnostic primitives per CLAUDE.md Logger-privacy rule — `"download start url=... resumeOffset=... cachedBlob=... path=..."`, `"download success url=... statusCode=... resumeOffset=..."`, `"attachToInFlight tasks=... attached=..."`, `"cancel(url:) no-match url=..."`, `"cancel(url:) issued url=... resumeBlob=..."`, `"mergeIntoDestination 206 path: destination missing — callsite invariant violated. destination=... resumeOffset=..."`, `"updateResumeDataFromError url=... freshBlob=... errorDomain=... errorCode=..."`. Plus inline resume-path labels embedded in those format strings — `"withResumeData"`, `"rangeHeader"`, `"fresh"`. Diagnostic-only, never user-facing UI. Per #340 slice-8 decision. |
| `SharedScenariosListView` middle-dot separator (1 candidate) | `Pastura/Pastura/Views/Community/SharedScenarios/SharedScenariosListView.swift` (scenario row meta line, between category name and `~%lld inferences` count) | **Permanent** — Typographic separator glyph (`·`, U+00B7 MIDDLE DOT) used as a category/metric joiner. Universal across locales; no translator value. Same shape as `InferenceStatsFormatter` `•` (U+2022) per slice-6 precedent. Per #340 slice-9 decision. |
| `current_event` TextField placeholder | `Pastura/Pastura/Views/Editor/PhaseEditorSheet+EventInjectSection.swift:51` | **Permanent** — placeholder text is the literal `eventVariable` default value the phase falls back to when the field is empty (see inline comment lines 48–50 and the section footer copy). Localizing would diverge from the model-layer default, breaking the curator's mental model that the placeholder = the YAML token written when blank. Per #340 slice-10 decision. |
| `accessibilityIdentifier("editor.*")` UI-test selectors | `Pastura/Pastura/Views/Editor/ScenarioEditorView.swift:99,122` | **Permanent** — `accessibilityIdentifier(_:)` strings are UI-test programmatic selectors consumed by `PasturaUITests` (e.g., `EditorReloadTests`), NOT VoiceOver-spoken labels (those go through `accessibilityLabel(_:)`, which IS wrapped). Identifier stability over locale display per PR #376 memory `feedback_i18n_a11y_label_triage` (`accessibilityLabel` vs `accessibilityIdentifier` distinction). Per #340 slice-10 decision. |
| `LlamaCppService` Logger + signpost + KV-cache mode tokens (17 candidates) | `Pastura/Pastura/LLM/LlamaCppService.swift` | **Permanent** — Three sub-classes: (a) `os.Logger` subsystem / category strings — `"com.tyabu12.Pastura"` × 3, `"LlamaCppService"`, `"StreamingDiag"`, `"LlamaCppRuntime"` (the last is the llama.cpp C-runtime log-capture channel installed via `llama_log_set`). (b) `os.signpost` trace labels passed as plain `StaticString`-like literals — `"loadModel"`, `"unloadModel"`, `"generateStream"`. (c) `os.Logger.debug` interpolations annotated `privacy: .public` per CLAUDE.md Logger-privacy rule — `"streamCheckpoint mode=… tokens=… tail=…"` (DEBUG-only per-loop checkpoint), `"decodeFailureError: result=…, suspendRequested=…"` (Metal decode-failure diagnostic), `"generate enter: isModelLoaded=…, …"`, `"generate post-throttle: …"`, `"generate throwing .notLoaded: …"` (load/reload race-investigation trace), `"<stopSequence> stop sequence detected — ending generation/stream early"` × 2 (interpolated form). Plus the KV-cache mode label (`"non-stream"`) used as the signpost `mode=` argument value. Diagnostic-only, never user-facing UI strings. Per #340 slice-11 decision. |
| `LlamaCppService+Sampler` stderr capture diagnostics + precondition fail-fast (10 candidates) | `Pastura/Pastura/LLM/LlamaCppService+Sampler.swift` | **Permanent** — Three sub-classes: (a) `preconditionFailure("Failed to initialize sampler chain")` at L44 — programmer error in `llama_sampler_chain_init`; fires only on llama.cpp internal failure to allocate the chain. (b) `LLMError.invalidGrammar(description: "createSampler: grammar supplied without vocab")` at L69 — programmer-defect fail-fast diagnostic; the current 2 callers (`runGeneration`, `runStreamGeneration`) always pass `vocab` alongside `grammarString`. Identifier-leading `"createSampler:"` is a function-name diagnostic, not user copy. (c) stderr-redirect failure diagnostic strings (L167/L170/L181/L187/L214 errno warnings — `"stderr capture skipped: dup(STDERR_FILENO) failed errno=…"`, `"stderr capture skipped: dup2 failed errno=…"`, `"stderr restore (dup2) failed errno=… — fd 2 may be invalid"` plus the matching sentinel return values `"<stderr capture skipped: dup failed errno=…>"`, `"<stderr capture skipped: dup2 failed errno=…>"`). Plus the L91 multi-line `logger.error` GBNF-source debug-dump (`privacy: .public`) printed verbatim — its body content is grammar source (English-only by construction). Plus L228-229 non-UTF-8 hex-fallback sentinel (`"<non-UTF-8 stderr capture: %@ bytes; "` + `"hex prefix: "`). All diagnostic-only or programmer-defect fail-fast paths. The L102 `"GBNF grammar parse failed: %@"` ALSO surfaces through `LLMError.invalidGrammar` BUT is genuinely user-reachable on grammar-builder defects (PR #368 was one such case), so that one IS wrapped — see catalog. Per #340 slice-11 decision. |
| `OllamaService` whole file — dev-only Ollama HTTP backend (16 candidates) | `Pastura/Pastura/LLM/OllamaService.swift` | **Permanent — dev-only backend per ADR-005 §8**; whole file gated by `#if DEBUG \|\| targetEnvironment(simulator)` (L5–L220) so symbols are absent from App-Store-Connect-review-bound Release-iphoneos archives. Five sub-classes: (a) Ollama wire identifier `"gemma4:e2b"` (default model name). (b) `preconditionFailure("Static default URL literal is invalid")` at L45 — programmer-bug fail-fast. (c) Backend identifier `"Ollama"` (returned from `backendIdentifier`; used for export metadata). (d) HTTP / JSON wire tokens — `"v1/chat/completions"` (path), `"POST"` (method), `"application/json"` (Content-Type value), `"Content-Type"` (header name), `"temperature"`, `"max_tokens"` (request-body JSON keys), `"completion_tokens"` (response-body JSON key), `"<binary>"` fallback × 2 (non-UTF-8 response-body decoder fallback). (e) `LLMError.networkError` / `LLMError.generationFailed` description payloads — `"Non-HTTP response received"` × 2 (URLResponse type guard fail), `"HTTP %lld: client error"` (4xx mapping), `"HTTP %lld: server error"` (5xx mapping). All never reach Release users — Ollama backend is selected only via the `OLLAMA_INTEGRATION` Xcode scheme env-var in development. Per #340 slice-11 decision. |
| `Data/` + `Data/Models/` whole bucket (~81 candidates) | `Pastura/Pastura/Data/DatabaseManager.swift`, `Pastura/Pastura/Data/{Turn,CodePhaseEvent,Scenario,Simulation}Repository.swift`, `Pastura/Pastura/Data/Models/{ScenarioRecord,SimulationRecord,CodePhaseEventRecord}.swift` | **Permanent** — GRDB schema strings bound by SQL contract, never reach UI. Four sub-classes: (a) table names (`scenarios`, `simulations`, `turns`, `code_phase_events`) — used as `databaseTableName` static + `Column` initializers, `CREATE TABLE` SQL identifiers, and FK reference targets. (b) column names (`simulationId`, `roundNumber`, `phaseType`, `agentName`, `rawOutput`, `parsedOutputJSON`, `sequenceNumber`, `createdAt`, `updatedAt`, `scenarioId`, `currentRound`, `currentPhaseIndex`, `stateJSON`, `configJSON`, `yamlDefinition`, `isPreset`, `modelIdentifier`, `llmBackend`, `sourceType`, `sourceId`, `sourceHash`, `payloadJSON`, `phasePathJSON`) — GRDB `Column` initializer args + SQL `CREATE TABLE`/`ALTER TABLE`/`CREATE INDEX` column references. (c) index names (`idx_turns_simulation_round`, `idx_code_phase_events_simulation_round`) — SQL `CREATE INDEX` identifiers; rename = migration. (d) migration version IDs (`v1_createTables`, `v2_addSequenceNumberToTurns`, `v3_addModelInfoToSimulations`, `v4_addScenarioSourceColumns`, `v5_createCodePhaseEventsTable`, `v6_addPhasePathToTurnsAndCodePhaseEvents`) — GRDB `DatabaseMigrator.registerMigration` keys; permanent identifiers (changing them re-runs migrations or leaves orphaned `grdb_migrations` rows). Plus: `DataError.recordNotFound(type:)` class-name argument `"SimulationRecord"` × 2 (`SimulationRepository.swift:70/83`) — English type-tag debug-info interpolated into the localized `Record not found: %@ id=%@` parent template (same shape as `LLMError.generationFailed(description:)` debug-info payloads). Per #340 slice-12 decision. |
| `Models/` wire-format / Codable / programmer-defect bucket (~24 candidates) | `Pastura/Pastura/Models/{AnyCodableValue,AssignTarget,GalleryScenario,ModelDescriptor,OutputSchema,Pairing,PhaseType,ScenarioConventions,ScoreCalcLogic,TurnOutput}.swift` | **Permanent — wire-only by current architecture** (NOT a script-level `EXCLUDED_PATH_PREFIXES` addition; audit visibility preserved for future Models user-facing leak). Models display paths route through the Views layer (e.g., `GalleryCategory.displayName` is defined at `Pastura/Pastura/Views/Community/SharedScenarios/SharedScenariosListView.swift:183`, NOT on the Models enum). Sub-classes: (a) enum raw values used as YAML/JSON wire tokens — `random_one`, `round_robin`, `speak_all`/`speak_each`/`score_calc`/`event_inject`, `social_psychology`/`game_theory`/`experimental`, `prisoners_dilemma`/`vote_tally`/`wordwolf_judge`. (b) Codable CodingKey strings — `recommended_model`, `estimated_inferences`, `yaml_sha256`, `updated_at`. (c) Output-schema canonical field names — `statement`, `inner_thought`. (d) GGUF filename regex `^[A-Za-z0-9._-]+\.gguf$`. (e) programmer-defect fail-fast — `AnyCodableValue` Codable typeMismatch `debugDescription` (`"Expected String, [String], [String: String], or [[String: String]]"`) + `ModelDescriptor.init` `preconditionFailure("ModelDescriptor.fileName must match ...")`. Per #340 slice-12 decision. |
| `Models/TurnOutput.primaryText` universal joiners (2 candidates) | `Pastura/Pastura/Models/TurnOutput.swift:97-98` (`" (\($0))"` paren-wrap + `"→ \(voted)\(reasonPart)"` arrow composite) | **Permanent — EXPLICIT EXCEPTION** to the `Models/` wire-only carve-out above. `primaryText(for:)` is consumed by live UI (`Pastura/Pastura/Views/Components/AgentOutputRow.swift:701`, `Pastura/Pastura/App/SimulationViewModel.swift:919`) and markdown export (`Pastura/Pastura/App/ResultMarkdownExporter.swift:431`), so unlike (a)-(d) above it IS user-facing. The joiners stay ASCII (space, parentheses, U+2192 right arrow `→`) because the wrapped content (`voted` persona name + `reason` LLM text) is `scenario.language`-bound — wrapping fullwidth `（）` around English LLM output (en scenario on ja-locale device) produces a worse visual artifact than ASCII `(...)` around Japanese LLM output (ja scenario on en-locale device). Same shape as ResultMarkdownExporter slice-4 `%@ → %@` / `%@ (%@)` precedent. Per #340 slice-12 decision. |
| `App/ModelManager.swift` Logger + identifier residual (7 candidates after slice-12 wraps) | `Pastura/Pastura/App/ModelManager.swift` | **Permanent** — Same shape as the `ModelDownloader` carve-out above (slice 8). Three sub-classes: (a) `os.Logger` subsystem / category strings — `"com.tyabu12.Pastura"`, `"ModelManager"`. (b) Persistence + file-system identifiers — `"com.pastura.activeModelID"` (UserDefaults key for the persisted active model id), `".download"` (the staged-download filename suffix used to gate cellular-consent re-prompts). (c) Logger format strings carrying `privacy: .public` interpolations per CLAUDE.md Logger-privacy rule — `"attach: catalog miss — url=... — cancelling"`, `"attach: cellular without consent — descriptor=... — cancelling for consent re-prompt"`, `"attach: defensive cancel — descriptor=... stateNotNotDownloaded"`. Slice-8 sibling — the 3 user-facing `.error(String)` literals in `verifyDownloadIntegrity` were wrapped in slice 12; everything else in the file is diagnostic-only. Per #340 slice-12 decision. |
| `App/PlaybackSpeed.swift` multiplier labels (3 candidates) | `Pastura/Pastura/App/PlaybackSpeed.swift:89-91` (`"x0.5"`, `"x1"`, `"x1.5"`) | **Permanent** — Universal multiplier notation across locales (Netflix / YouTube / Apple TV playback-control convention); no translator value. Same shape as `InferenceStatsFormatter` `tok/s`/`s` carve-out (slice 6). Canonical convention statement lives in the `PlaybackSpeed.label` doc-comment at the source file; `PlaybackSpeedTests.labels` literal-pins `"x0.5"`/`"x1"`/`"x1.5"` as the regression guard against accidental wrap. `.instant` case label `"Max"` IS wrapped via `String(localized: "Max")` (ja: `最速`) because "Max" is plain English, unlike the multiplier-notation siblings — slice-12 asymmetric-wrap precedent codified inline. Per #340 slice-12 decision. |
| `LlamaCppService+{ChatTemplate,Lifecycle,Prefill,Thermal,Tokenization,Trace}.swift` sibling-extension family (~25 candidates) | `Pastura/Pastura/LLM/LlamaCppService+{ChatTemplate,Lifecycle,Prefill,Thermal,Tokenization,Trace}.swift` | **Permanent** — Extension of slices 8 + 11 carve-out shape to the remaining `LlamaCppService+*.swift` siblings. Two sub-classes: (a) `os.Logger` `info` / `notice` / `warning` interpolations annotated `privacy: .public` per CLAUDE.md Logger-privacy rule — function-name + state diagnostics like `"%arg() called while generate() in flight — awaiting completion"`, `"%arg() timed out after %args — proceeding despite in-flight generate"` (Lifecycle); thermal-state pause `"Thermal state %arg — inserting 200ms pause"` (Thermal); tokenization retry-drop trace `"decodePieceRaw: retry also returned non-positive (%arg) — a token was silently dropped from the stream"` (Tokenization); trace-file failure paths `"trace: could not resolve Documents directory"`, `"trace: write failed: %arg"` (Trace); env-var name `"PASTURA_TRACE_LLM"` + trace filename template `"llm-trace-%arg-%arg.json"` (Trace). (b) `LLMError.generationFailed(description:)` debug-info payloads — `"Memory allocation failed for chat template"`, `"llama_chat_apply_template failed to calculate buffer size"`, `"llama_chat_apply_template failed"`, `"llama_chat_apply_template returned %arg bytes of invalid UTF-8"` (ChatTemplate); `"Tokenization failed"` (Tokenization); `"Empty token buffer should have been caught by context-size check"` (Prefill preconditionFailure). All English description payloads are interpolated into the localized `Generation failed: %@` parent template (same shape as `DataError.recordNotFound(type:)` debug-info above). Diagnostic-only, never user-facing UI strings. Per #340 slice-12 decision. |
| `LLM/GBNFGrammarBuilder.swift` + `JSONResponseParser.swift` parser internals (~12 candidates) | `Pastura/Pastura/LLM/GBNFGrammarBuilder.swift`, `Pastura/Pastura/LLM/JSONResponseParser.swift` | **Permanent** — Parser-internal wire-format source strings, never reach UI. Three sub-classes: (a) GBNF grammar source strings — `"root ::= %arg"`, `"%arg-value"`, `"%arg-value ::= %arg"`, escape-template `"\"%arg\""`, JSON value/string/ws/trailing rule literals (`"string ::= \"\\\"\" ( [^\"\\\\] | ... )* \"\\\"\""`, `"ws ::= ([ \\t\\n] ws)?"`, `"trailing ::= ([\\t\\n\\r -~] trailing)?"`). Consumed by llama.cpp's GBNF sampler; format bound by llama.cpp library, not localizable. (b) JSON regex patterns for stripping LLM scratch / thinking markers + code fences — `"<\\|channel>thought\\s*.*?<channel\\|>"`, `"<think>.*?</think>"`, `"<\\|im_end\\|>.*"`, `` "```(?:json)?\\s*\\n?(.*?)\\n?```" ``. Wire-format input format detection; same regex string is reused in `PartialOutputExtractor.swift` (next row). (c) JSON parse error codes `"unclosed_string"` / `"unclosed_brace"` — Pastura-internal `JSONResponseError.malformed` discriminators consumed by retry-policy code, not UI. Per #340 slice-12 decision. |
| `LLM/{MockLLMService,PartialOutputExtractor,SuspendController,LlamaCppTraceFixture}.swift` test+inline helpers (~5 candidates) | `Pastura/Pastura/LLM/MockLLMService.swift`, `Pastura/Pastura/LLM/PartialOutputExtractor.swift`, `Pastura/Pastura/LLM/SuspendController.swift`, `Pastura/Pastura/LLM/LlamaCppTraceFixture.swift` | **Permanent** — Test-time + programmer-defect + wire-format. Four sub-classes: (a) `MockLLMService` test-fixture diagnostic preconditionFailure — `"MockLLMService exhausted: %arg calls made, only %arg responses available"`, `"MockLLMService streamChunks exhausted: %arg stream calls made, only %arg configured"`. (b) `PartialOutputExtractor` field-name + token-prefix internals — `"statement"`, `"inner_thought"` (schema field names, same shape as `Models/OutputSchema.swift` row above), `"<\|channel>"`, `"<think>"` (thinking-mode token prefixes), `"\"%arg\""` (JSON string-escape template), plus the regex strings shared with `JSONResponseParser.swift`. (c) `SuspendController.preconditionFailure("SuspendController: multi-awaiter not supported (1 generate = 1 waiter)")` — concurrent-usage fail-fast. (d) `LlamaCppTraceFixture` wire-format version marker `"pastura-llm-trace/v1"` — JSON `schema_version` value for the trace replay format. Per #340 slice-12 decision. |
| `Utilities/ReportURLBuilder.swift` external-service wire tokens (5 candidates) | `Pastura/Pastura/Utilities/ReportURLBuilder.swift` | **Permanent** — Sub-classes: (a) external-service identifiers — Google Forms entry id `"1FAIpQLSfsZkY9-R3QxqVfdXSzsUnx3SXR-g9O7DxjdN-1-VtMjMXSAw"` (form `entry.<id>` field key bound by Google Forms), GitHub repo slug `"tyabu12/pastura"` (URL path component), GitHub label `"shared-scenario-report"` (label-name identifier in GitHub issue API). (b) email-subject structured tag `"[Shared Scenario Report]"` (with `%arg` scenario-name suffix variant) — square-bracket prefix is universal across locales (GitHub `[bug]` labels, mailing-list `[announcement]` convention) and the `%arg` interpolated scenario name is `scenario.language`-bound (same logic as `TurnOutput.primaryText` joiner exception above). Per #340 slice-12 decision. |
| `App/` Logger + identifier sweep (6 sibling files) | `Pastura/Pastura/App/{AppDependencies,CellularConsentStore,DownloadDelegate,FeatureFlags,NetworkPathMonitor,SimulationActivityRegistry}.swift` | **Permanent** — Same shape as the `ModelManager` carve-out above (slice 12). Three sub-classes: (a) `os.Logger` subsystem / category strings — `DownloadDelegate.swift:88` `"com.tyabu12.Pastura"` + `"DownloadDelegate"`. (b) Identifier strings bound by Apple-platform APIs — `CellularConsentStore.swift:25` UserDefaults key `"com.pastura.hasCellularDownloadConsent"`, `FeatureFlags.swift:26-27` UserDefaults keys `"realtimeStreamingEnabled"` / `"backgroundContinuationEnabled"` (load-bearing per `FeatureFlags` doc-comment — renaming silently unbinds developer-side `defaults write` overrides), `NetworkPathMonitor.swift:69` dispatch-queue label `"com.pastura.NetworkPathMonitor"`, `AppDependencies.swift:174` application-support directory name `"Pastura"`. (c) `preconditionFailure` programmer-defect fail-fast — `AppDependencies.swift:87` `"AppDependencies requires an explicit llmService in Release builds"` (Release-iphoneos build-config guard per ADR-005 §8), `SimulationActivityRegistry.swift:59` `"SimulationActivityRegistry.leave() called without matching enter()"` (counter-symmetry invariant). Plus `DownloadDelegate.swift` Logger format strings carrying `privacy: .public` interpolations per CLAUDE.md Logger-privacy rule — L245 `"didFinishDownloadingTo: failed to move staged temp — taskID=%arg errorCode=%arg"`, L264 `"didFinishDownloadingTo: unregistered taskID=%arg — staged file may leak"`, L294 `"didCompleteWithError: unregistered taskID=%arg — ignoring (no PerTaskState in map)"`. Diagnostic-only / programmer-defect, never user-facing UI. Per #340 slice-13 decision. |
| `App/` Logger + wire-format / bundle-resource sweep (3 sibling files) | `Pastura/Pastura/App/{PresetLoader,URLSessionGalleryService,ContentBlocklist}.swift` | **Permanent** — Mixed Logger + HTTP wire + bundle-resource carve-out. Three sub-classes: (a) `os.Logger` `%public` interpolations per CLAUDE.md Logger-privacy rule — `PresetLoader.swift:10-11` subsystem/category, L57 `"PresetLoader: %arg.yaml not found in bundle"`, L82 `"PresetLoader: failed to load %arg: %arg"`. (b) HTTP / URL / env-var wire tokens — `URLSessionGalleryService.swift:43` env-var name `"PASTURA_GALLERY_BASE_URL"`, L50 default gallery index URL literal (compile-time constant), L131 HTTP method `"GET"`, L133 HTTP header name `"If-None-Match"`, L151 HTTP header name `"ETag"`, L218 scheme allowlist `"https"`, L242 SHA-256 hex format `"%02x"`, L52 programmer-defect `preconditionFailure("Invalid gallery index URL literal")`. (c) Bundle resource + JSON-Decoder fail-fast paths — `ContentBlocklist.swift:59` precondition `"ContentBlocklist.inputPatterns is empty after partition — check categoriesExcludedFromInput vs source.json categories"`, L109/L116 preconditionFailure on missing/unparseable `ContentBlocklist.json` (ADR-005 §4.4 fail-fast contract — silent degradation would disable the input layer). Plus `PresetLoader.swift:19-28` preset file basenames (`prisoners_dilemma`, `bokete`, `word_wolf`, `target_score_race`, plus `_en` siblings) — bundle resource filenames, NOT user copy (the localized scenario `name` field is the JA / EN sibling pair per ADR-010 D3). Diagnostic-only / wire-format / programmer-defect, never user-facing UI. Per #340 slice-13 decision. |
| `App/` external-tool input + internal path-template internals (2 files) | `Pastura/Pastura/App/ImportViewModel.swift`, `Pastura/Pastura/App/ScenarioContentValidator.swift` | **Permanent** — External-tool prompt + internal diagnostic field-paths. Two sub-classes: (a) `ImportViewModel.scenarioGenerationPrompt` (L138-165, 24-line `static let`) — verbatim prompt template **passed to an external LLM via clipboard** (user copies to ChatGPT / Claude / etc. to generate a Pastura YAML scenario). ADR-010 §4 Engine exclusion analog: content is structurally bound by what the receiving LLM should output (Pastura YAML schema with `phase_type` discriminators + `language: ja|en` directive). MUST stay English regardless of user locale because (1) curated example scenarios are bilingual via sibling YAMLs, (2) the embedded YAML field names (`id`, `language`, `personas`, `phases`, …) are wire-format tokens consumed by `ScenarioLoader`. Same shape as slice-11 LLM-bucket decision. (b) `ScenarioContentValidator.swift:195/L202` JSON-path key templates `"%arg.then.%arg"` / `"%arg.else.%arg"` — conditional-phase recursion position labels (e.g., `2.then.1`, `2.else.3`) embedded as the `%arg` position interpolation inside localized findings like `"Phase %arg prompt contains a term that is not allowed"`. Field-path internals, not user-readable English prose. Per #340 slice-13 decision. |
| `App/DeepLink/DeepLinkURL.swift:12` alphabet constant (1 candidate) | `Pastura/Pastura/App/DeepLink/DeepLinkURL.swift` | **Permanent** — Character-class constant `"abcdefghijklmnopqrstuvwxyz"` used to construct the allowed-id alphabet for `pastura://scenario/<id>` URL validation per the type doc-comment regex `^[a-z0-9_]+$`. Not user-facing copy; localizing the alphabet would break the URL spec. Per #340 slice-13 decision. |
| `App/UITestSupport/` fixtures + DEBUG-gated entry-point error (3 entries) | `Pastura/Pastura/App/UITestSupport/{StubGalleryService,StubScenarioSeeder}.swift`, `Pastura/Pastura/PasturaApp.swift:523` | **Permanent — `--ui-test`-gated UI-test fixture / DEBUG-only entry-point error**. Three sub-classes: (a) UI-test fixture YAML + IDs — `StubGalleryService.canaryYAML` (L51-69) + `canaryYAMLURL` (`"stub://gallery/canary.yaml"`) + scenario id `"ui_test_canary"`; `StubScenarioSeeder.homeSeedYAML` (L62-80) + `editorSeedYAML` (L86-104) + persona names (`Alice`, `Bob`, `Carol`, `Dave` — same shape as the `SheepAvatar` Preview-only `Character` carve-out above). Both files are wrapped in `#if DEBUG` and consumed only by `PasturaUITests` (canary navigation + Home seed + editor reload tests). (b) UI-test bootstrap fatal-error literal — `StubGalleryService.swift:44` `fatalError("Canary YAML URL literal failed to parse")` (compile-time literal failure-impossible by construction; project bans `!` so the guard is explicit). (c) `PasturaApp.swift:523` `appState = .error("UI test setup failed: \(error.localizedDescription)")` — DEBUG entry-point error inside `setupUITestState()` body. **Two-gate condition** `#if DEBUG` (L500) AND `CommandLine.arguments.contains("--ui-test")` (L385); routes into `Text(message)` at L220 only inside `PasturaUITests`-launched processes, never reaches end users. The asymmetry with the production-path siblings L404 / L496 (Database error: `do/catch` in `initialize()` / `finalizeInit()`) and L479 (No active model descriptor: `guard let descriptor` in `finalizeInit()`) — all wrapped in slice-13 — is intentional: the production `.error` paths fire in real user flows, while L523 fires only inside `xctest` host processes. Same gating pattern as the StubGalleryService / StubScenarioSeeder fixtures. Per #340 slice-13 decision. |

### Self-test

`python3 scripts/check_i18n_potential_keys.py --self-test` exercises 38
fixtures across four families:

- **Key-text noise filters (26)** — TP + FP pairs per `NOISE_FILTERS`
  category, plus real-leak smoke tests using PR #288's
  `phaseTypeDescription` strings.
- **Path-exclusion (4)** — `Engine/` (ADR-010 §4), `+Previews.swift`
  filename suffix, `App/` kept, `+Helpers.swift` kept.
- **`#Preview` block-skip (7)** — TP / FP / nested closure / traits arg
  / multi-line opening brace / unterminated block / etc.
- **Filter precedence (1)** — confirms `+Previews.swift` filename
  exclusion takes precedence over the content-based `#Preview` filter
  so the two don't double-count.

CI does not run the self-test, but contributors editing the filter
logic should.

### CI gating

Tier 2 is **not** a CI gate. The signal-to-noise ratio (~5–15% real
leaks per PR #288's audit) is too low to enforce. Two viable
integration patterns deferred to a future change:

- **PR-comment bot**: post `git diff …` newly-introduced `__PotentialKeys`
  as a non-blocking comment. Reviewer judges.
- **`code-reviewer` subagent context**: include the script's diff-mode
  output in the LLM reviewer's input. Semantic judgement vs syntactic
  filter.

For now, Tier 2 is opt-in: invoke locally before opening a PR that adds
new view-model surface, new `Text(_:)` of computed values, or new helper
functions returning display-bound `String`.

### Extension protocol — adding filters

Two filter shapes coexist in `check_i18n_potential_keys.py`:

**Key-text filters** (`NOISE_FILTERS`)

Evaluate against the literal key string alone — no source-location
context. Open `check_i18n_potential_keys.py`, add a regex/predicate to
`NOISE_FILTERS`, and add **one TP fixture (drops as expected) plus one
FP fixture (does NOT drop) to `_self_test`**.

**Location-based filters** (e.g. `apply_preview_filter`)

Evaluate against `(file, line)` — required when the filtering decision
depends on where the literal lives, not just what it says. Add a sibling
pass in `main()` BEFORE `filter_candidates()`; surface the dropped count
as a separate row in `format_summary()`. Self-test fixtures operate on
in-memory source text (not extracted keys) and live in a dedicated
section of `_self_test()`. Include a **path-exclusion regression
fixture** asserting that the existing filename filter still takes
precedence — without it, a future contributor moving `+Previews.swift`
under the location filter would silently double-count.

With ~85% noise floor, silent regressions in either filter shape
re-classify real leaks as noise — self-test fixtures are the only
barrier against this. The pattern mirrors
`scripts/check_localization_coverage.py` (Tier 3 sibling).

## Tier 3 — coverage gate (reference)

**Where**: `scripts/check_localization_coverage.py`, shipped in
[PR #299](https://github.com/tyabu12/pastura/pull/299).
**Runs**: CI `localization-coverage` job, fails on any uncovered key.
Different concern (translation completeness vs. wrap detection) but
listed here for the architecture map.

## Tripwire vs. coverage — why the distinction matters

It is tempting to widen Tier 1's regex toward Tier 2's coverage goal.
**Don't.** The empirical lesson from PR #288:

- The catalog had 1808 entries, of which 1235 were unique `__PotentialKeys`
- Apply syntactic noise filters → 669
- Apply directory exemptions → 548
- Limit to Views/App + non-audit-list → 202
- Manual triage → ~10–30 real leaks

The 5–15% signal ratio is fundamental, not a tooling failure. Tier 1's
narrow regex extracts the high-signal cases (~80% of empirical leaks
were `errorMessage = "..."` shape) at zero false-positive cost; Tier 2
finds the remainder at a triage cost. Mixing them — making Tier 1
coverage-y or Tier 2 a CI gate — degrades both: Tier 1 starts blocking
merges on noise, Tier 2 stops being run because `swiftlint` is the more
visible authority and its silence reads as "all clear."

## Decision matrix — which tier to think about

| Adding... | Tier to think about |
|-----------|---------------------|
| New ViewModel with `errorMessage: String?` | **Tier 1**: append property name to regex |
| New helper returning display-bound `String` | **Tier 2**: run audit before PR |
| New `Text("Foo")` literal | All Xcode versions auto-extract this; verify catalog has the key with `ja` value (Tier 3 will fail otherwise) |
| New `String(localized: "Foo")` call | **Tier 3**: run `python3 scripts/check_localization_coverage.py` |
| New `+Previews.swift` preview body | None — excluded by Tier 2's filename-suffix filter |
| New file under `Engine/` | None for catalog (ADR-010 §4); the per-Engine-site translation table in ADR-010 § Step C-1 governs Engine strings |

## See also

- ADR-010 — Localization (i18n: ja / en) — language-resolution priority,
  Engine exclusion, source-language commitment
- `docs/ROADMAP.md` § Localization Plan → Step A details — phase scope
  and PR sequencing
- PR #288 (i18n Step A-1) — initial audit + the 10 `phaseTypeDescription`
  unwrapped-helper-return cases that motivated Tier 2
- PR #299 (i18n Step A-2 1/2) — `localization-coverage` CI gate (Tier 3)
