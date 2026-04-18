import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct LLMErrorTests {
  // MARK: - Equatable

  @Test func loadFailedEquatable() {
    let lhs = LLMError.loadFailed(description: "disk read error")
    let rhs = LLMError.loadFailed(description: "disk read error")
    #expect(lhs == rhs)
  }

  @Test func loadFailedNotEqualWithDifferentDescription() {
    let lhs = LLMError.loadFailed(description: "disk read error")
    let rhs = LLMError.loadFailed(description: "network error")
    #expect(lhs != rhs)
  }

  @Test func generationFailedEquatable() {
    let lhs = LLMError.generationFailed(description: "timeout")
    let rhs = LLMError.generationFailed(description: "timeout")
    #expect(lhs == rhs)
  }

  @Test func notLoadedEquatable() {
    #expect(LLMError.notLoaded == LLMError.notLoaded)
  }

  @Test func invalidResponseEquatable() {
    let lhs = LLMError.invalidResponse(raw: "garbage")
    let rhs = LLMError.invalidResponse(raw: "garbage")
    #expect(lhs == rhs)
  }

  @Test func networkErrorEquatable() {
    let lhs = LLMError.networkError(description: "connection refused")
    let rhs = LLMError.networkError(description: "connection refused")
    #expect(lhs == rhs)
  }

  @Test func suspendedEquatable() {
    #expect(LLMError.suspended == LLMError.suspended)
  }

  // MARK: - Different cases are not equal

  @Test func differentCasesNotEqual() {
    let loadFailed = LLMError.loadFailed(description: "error")
    let generationFailed = LLMError.generationFailed(description: "error")
    #expect(loadFailed != generationFailed)
  }

  @Test func suspendedNotEqualToOtherCases() {
    // Regression guard: pattern matching for `.suspended` must not accidentally
    // match other cases (e.g., generationFailed) when the engine layer branches
    // on retry-eligible vs fatal errors.
    #expect(LLMError.suspended != LLMError.notLoaded)
    #expect(LLMError.suspended != LLMError.generationFailed(description: ""))
  }

  // MARK: - Conforms to Error

  @Test func conformsToError() {
    let error: any Error = LLMError.notLoaded
    #expect(error is LLMError)
  }

  // MARK: - LocalizedError

  @Test func conformsToLocalizedError() {
    #expect((LLMError.notLoaded as Any) is LocalizedError)
  }

  @Test func loadFailedErrorDescription() {
    let error = LLMError.loadFailed(description: "disk read error")
    #expect(error.errorDescription?.contains("disk read error") == true)
    #expect(error.errorDescription?.contains("load") == true)
  }

  @Test func generationFailedErrorDescription() {
    let error = LLMError.generationFailed(description: "timeout")
    #expect(error.errorDescription?.contains("timeout") == true)
    #expect(error.errorDescription?.contains("Generation") == true)
  }

  @Test func notLoadedErrorDescription() {
    let error = LLMError.notLoaded
    #expect(error.errorDescription?.contains("not loaded") == true)
  }

  @Test func invalidResponseErrorDescriptionShortRaw() {
    let raw = "bad json"
    let error = LLMError.invalidResponse(raw: raw)
    #expect(error.errorDescription?.contains("bad json") == true)
    #expect(error.errorDescription?.contains("Invalid") == true)
  }

  @Test func invalidResponseErrorDescriptionTruncatesLongRaw() {
    let raw = String(repeating: "x", count: 300)
    let error = LLMError.invalidResponse(raw: raw)
    let description = error.errorDescription ?? ""
    #expect(description.contains("...") == true)
    // Prefix of raw included in the description (first 200 chars), plus "..." = 203 chars max for the raw portion
    let prefix200 = String(raw.prefix(200))
    #expect(description.contains(prefix200) == true)
  }

  @Test func networkErrorErrorDescription() {
    let error = LLMError.networkError(description: "connection refused")
    #expect(error.errorDescription?.contains("connection refused") == true)
    #expect(error.errorDescription?.contains("Network") == true)
  }

  @Test func suspendedErrorDescription() {
    let error = LLMError.suspended
    // The suspended case is cooperative, not fatal — description should reflect that
    let description = error.errorDescription ?? ""
    #expect(description.contains("suspend") == true || description.contains("retry") == true)
  }
}
