import Testing

@testable import Pastura

struct LLMErrorTests {
  // MARK: - Equatable

  @Test func loadFailedEquatable() {
    let a = LLMError.loadFailed(description: "disk read error")
    let b = LLMError.loadFailed(description: "disk read error")
    #expect(a == b)
  }

  @Test func loadFailedNotEqualWithDifferentDescription() {
    let a = LLMError.loadFailed(description: "disk read error")
    let b = LLMError.loadFailed(description: "network error")
    #expect(a != b)
  }

  @Test func generationFailedEquatable() {
    let a = LLMError.generationFailed(description: "timeout")
    let b = LLMError.generationFailed(description: "timeout")
    #expect(a == b)
  }

  @Test func notLoadedEquatable() {
    #expect(LLMError.notLoaded == LLMError.notLoaded)
  }

  @Test func invalidResponseEquatable() {
    let a = LLMError.invalidResponse(raw: "garbage")
    let b = LLMError.invalidResponse(raw: "garbage")
    #expect(a == b)
  }

  @Test func networkErrorEquatable() {
    let a = LLMError.networkError(description: "connection refused")
    let b = LLMError.networkError(description: "connection refused")
    #expect(a == b)
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
