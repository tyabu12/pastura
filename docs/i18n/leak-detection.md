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
   | `url-or-path` | `https://…`, `/Users/…`, `~/Library` |
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
