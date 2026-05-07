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
 |descriptionError|conditionError|promptError|outcomeAlert|deepLinkError)
\s*[+=]+\s*\[?\s*"[^"]+"
```

against any file under `Pastura/Pastura/`. The 10 property names are an
**empirical** list, drawn from the PR #288 audit and the four
`SimulationViewModel*.swift` wraps fixed in PR #299. The narrow scope is
the entire point: widening to all `String` assignments re-introduces the
noise floor that PR #288's analysis was unable to cut through.

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
the remainder against the actual call site to decide *intentional Japanese
marketing copy* (e.g. PromoCard `ダウンロードが中断しました`), *internal log
strings* (Logger `%public` interpolations), or *real wrap leaks* (e.g.
`SimulationView.swift:535 loadError = "Scenario not found"`).

### Self-test

`python3 scripts/check_i18n_potential_keys.py --self-test` exercises 30
fixtures: a TP + FP pair per noise category, plus path-exclusion checks
for `Engine/` and `+Previews.swift`, plus real-leak smoke tests using
the PR #288 `phaseTypeDescription` strings. CI does not run the
self-test, but contributors editing the filter logic should.

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

Open `check_i18n_potential_keys.py`, add a regex/predicate to
`NOISE_FILTERS`, and add **one TP fixture (drops as expected) plus one
FP fixture (does NOT drop) to `_self_test`**. With ~85% noise floor,
silent regressions in the filter logic re-classify real leaks as noise
— self-test fixtures are the only barrier against this. The pattern
mirrors `scripts/check_localization_coverage.py` (Tier 3 sibling).

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
