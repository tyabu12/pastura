import Foundation
import NaturalLanguage
import PasturaCore

/// Headless-harness implementation of ``LanguageDetector``, backed by Apple's
/// `NLLanguageRecognizer` (available on macOS 15+, this package's platform).
///
/// This is the harness-side twin of `NLLanguageDetector` (App/). The harness
/// SwiftPM package reuses `Models`/`LLM`/`Engine` but **excludes** App/ (see
/// the root `Package.swift`), so it cannot reach the production concrete — yet
/// without a real detector injected, `LLMCaller.detectLanguageMismatch`
/// short-circuits on `guard let detector` and the `language_mismatch` metric is
/// 0 by construction in every harness run (issue #1234). `HarnessRunner`
/// injects this into `SimulationRunner`.
///
/// Why a separate concrete rather than sharing one: ADR-010 D8 forbids
/// `import NaturalLanguage` in the guarded LLM/ layer (CI-enforced by
/// `scripts/check_naturallanguage_axis.sh`), and ADR-023 §4 ports the
/// `LanguageDetector` protocol to `commonMain` while its `NaturalLanguage`
/// concrete stays platform-side — so "each consumer owns its concrete" is the
/// intended shape. The only semantically-tunable value, the confidence
/// threshold, is shared via ``LanguageDetectionDefaults`` (a pure `Double`,
/// D8-clean) so this and `NLLanguageDetector` cannot drift apart.
///
/// Implementation mirrors `NLLanguageDetector`: a fresh `NLLanguageRecognizer`
/// per call (avoids `reset()` / cross-call state accumulation), top-hypothesis
/// confidence gated at ``LanguageDetectionDefaults/confidenceThreshold``, and
/// default `languageHints` / `languageConstraints` (pinning would skew
/// confidence on the very cross-language drift cases the check exists to catch).
package final class HarnessLanguageDetector: LanguageDetector {
  package init() {}

  package func detect(text: String) -> String? {
    guard !text.isEmpty else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
    guard
      let (language, confidence) = hypotheses.first,
      confidence >= LanguageDetectionDefaults.confidenceThreshold
    else {
      return nil
    }
    return language.rawValue
  }
}
