import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ErrorReadabilityTests {
  // MARK: - Helper direct behavior

  @Test func prefersLocalizedErrorDescription() {
    struct LocalizedFake: LocalizedError {
      var errorDescription: String? { "human readable message" }
    }
    let result = readableDescription(LocalizedFake())
    #expect(result.contains("human readable"))
  }

  @Test func fallsBackWhenLocalizedErrorReturnsNil() {
    struct LocalizedNil: LocalizedError {
      var errorDescription: String? { nil }
    }
    // Falls through to String(describing:), which prints the type name for an
    // empty struct — we only assert the helper doesn't crash and returns
    // something non-empty.
    let result = readableDescription(LocalizedNil())
    #expect(!result.isEmpty)
  }

  @Test func fallsBackToStringDescribingForPlainError() {
    enum PlainError: Error { case boom }
    let result = readableDescription(PlainError.boom)
    #expect(result.contains("boom"))
  }

  // MARK: - Wrap-chain semantics at the Engine boundary

  // These tests assert that the helper preserves the inner error's meaningful
  // text when Engine wraps foreign errors into SimulationError. They inspect
  // the wrapped case's associated-value String directly rather than reading
  // `wrapped.localizedDescription` — that final surfacing step depends on
  // SimulationError adopting LocalizedError (landed in a subsequent commit)
  // and is exercised via the per-enum `errorDescription` tests. Keeping this
  // test focused on the helper's contribution makes it immune to the
  // conformance rollout order.

  @Test func wrapChainCarriesInnerLLMErrorText() {
    let inner = LLMError.generationFailed(description: "connection timeout")
    let wrapped = SimulationError.llmGenerationFailed(
      description: readableDescription(inner))
    guard case .llmGenerationFailed(let desc) = wrapped else {
      Issue.record("expected .llmGenerationFailed case")
      return
    }
    #expect(desc.contains("connection timeout"))
  }

  @Test func wrapChainCarriesLocalizedErrorText() {
    enum ValidatorThrown: LocalizedError {
      case missingSource(String)
      var errorDescription: String? {
        switch self {
        case .missingSource(let name): return "source '\(name)' not found"
        }
      }
    }
    let inner = ValidatorThrown.missingSource("topics")
    let wrapped = SimulationError.scenarioValidationFailed(
      readableDescription(inner))
    guard case .scenarioValidationFailed(let desc) = wrapped else {
      Issue.record("expected .scenarioValidationFailed case")
      return
    }
    #expect(desc.contains("source 'topics' not found"))
    // Prefers LocalizedError.errorDescription over the raw enum form —
    // guards against a regression to `"\(error)"` stringification.
    #expect(!desc.contains("missingSource("))
  }
}
