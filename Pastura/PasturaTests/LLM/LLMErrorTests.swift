import Testing

@testable import Pastura

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

  // MARK: - Different cases are not equal

  @Test func differentCasesNotEqual() {
    let loadFailed = LLMError.loadFailed(description: "error")
    let generationFailed = LLMError.generationFailed(description: "error")
    #expect(loadFailed != generationFailed)
  }

  // MARK: - Conforms to Error

  @Test func conformsToError() {
    let error: any Error = LLMError.notLoaded
    #expect(error is LLMError)
  }
}
