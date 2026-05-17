import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct SimulationErrorTests {
  // MARK: - LocalizedError conformance

  @Test func conformsToLocalizedError() {
    #expect((SimulationError.modelNotLoaded as Any) is LocalizedError)
  }

  // MARK: - errorDescription per case

  @Test func scenarioValidationFailedDescription() {
    let message = "invalid phase type"
    let error = SimulationError.scenarioValidationFailed(message)
    #expect(error.errorDescription?.contains("invalid phase type") ?? false)
  }

  @Test func llmGenerationFailedDescription() {
    // Issue #427 — the outer wrap that previously prepended
    // "LLM generation failed: " is removed. The inner description is expected
    // to be self-describing (typically a `LocalizedError.errorDescription`
    // routed via `readableDescription` from an inner `LLMError`).
    let error = SimulationError.llmGenerationFailed(description: "timeout")
    #expect(error.errorDescription == "timeout")
  }

  @Test func jsonParseFailedDescription() {
    let raw = String(repeating: "x", count: 50)
    let error = SimulationError.jsonParseFailed(raw: raw)
    #expect(error.errorDescription?.contains("parse failed") ?? false)
    #expect(error.errorDescription?.contains(raw) ?? false)
  }

  @Test func retriesExhaustedDescription() {
    let error = SimulationError.retriesExhausted
    #expect(error.errorDescription?.contains("retries") ?? false)
  }

  @Test func modelNotLoadedDescription() {
    let error = SimulationError.modelNotLoaded
    #expect(error.errorDescription?.contains("not loaded") ?? false)
  }

  @Test func cancelledDescription() {
    let error = SimulationError.cancelled
    #expect(error.errorDescription?.contains("cancelled") ?? false)
  }

  // MARK: - jsonParseFailed truncation

  @Test func jsonParseFailedTruncatesLongRaw() {
    let longRaw = String(repeating: "a", count: 300)
    let error = SimulationError.jsonParseFailed(raw: longRaw)
    let description = error.errorDescription ?? ""
    // Truncated to 200 chars + "..."
    #expect(description.contains("..."))
    // The raw portion should not exceed 200 + "..." = 203 chars past the prefix
    let prefix = "JSON parse failed: "
    let rawPortion =
      description.hasPrefix(prefix)
      ? String(description.dropFirst(prefix.count))
      : description
    #expect(rawPortion.count <= 203)
  }

  @Test func jsonParseFailedDoesNotTruncateShortRaw() {
    let shortRaw = String(repeating: "b", count: 100)
    let error = SimulationError.jsonParseFailed(raw: shortRaw)
    let description = error.errorDescription ?? ""
    #expect(!description.contains("..."))
    #expect(description.contains(shortRaw))
  }

  // MARK: - Wrap-chain prefix-collapse regression (#427)

  // Regression guards for issue #427: the chain
  //   LLMError → readableDescription(...) → SimulationError.llmGenerationFailed
  //   → .localizedDescription
  // must produce **exactly one** domain-prefix layer. Reverting either the
  // `SimulationEvent.swift` pass-through (Item 1) or the LlamaCppService
  // inner-description trim (Item 2) makes one of these tests fail.

  @Test func loadFailedWrapChainProducesSingleLayerPrefix() {
    let path = "/tmp/test-model.gguf"
    let inner = LLMError.loadFailed(description: path)
    let wrapped = SimulationError.llmGenerationFailed(
      description: readableDescription(inner))
    let final = wrapped.localizedDescription ?? ""
    let expected = String(format: String(localized: "Model load failed: %@"), path)
    #expect(final == expected)
  }

  @Test func generationFailedWrapChainProducesSingleLayerPrefix() {
    let detail = "connection timeout"
    let inner = LLMError.generationFailed(description: detail)
    let wrapped = SimulationError.llmGenerationFailed(
      description: readableDescription(inner))
    let final = wrapped.localizedDescription ?? ""
    let expected = String(format: String(localized: "Generation failed: %@"), detail)
    #expect(final == expected)
  }

  @Test func loadFailedInnerDescriptionCarriesRawContextNotProse() {
    // Convention: LLMError.loadFailed's inner description is raw context
    // (a path, an error code) — never a prose restatement of "failed".
    // The outer LLMError wrap "Model load failed: " already conveys the
    // failure category; an inner prose like "Failed to load model from"
    // stacks redundant wording (#427).
    let path = "/var/mobile/test.gguf"
    let err = LLMError.loadFailed(description: path)
    let desc = err.errorDescription ?? ""
    #expect(desc.contains(path))
    // The description portion (after the outer prefix) must not itself
    // begin with another "failed" / "Failed" verb — locale-agnostic by
    // anchoring to the localized prefix at runtime.
    let prefix = String(format: String(localized: "Model load failed: %@"), "")
    if let range = desc.range(of: prefix) {
      let innerPortion = String(desc[range.upperBound...])
      #expect(!innerPortion.lowercased().hasPrefix("failed"))
    }
  }
}
