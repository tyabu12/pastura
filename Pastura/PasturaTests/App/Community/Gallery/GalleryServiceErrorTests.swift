import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct GalleryServiceErrorTests {
  // MARK: - LocalizedError conformance

  @Test func conformsToLocalizedError() {
    #expect((GalleryServiceError.invalidResponse as Any) is LocalizedError)
  }

  // MARK: - errorDescription per case

  @Test func responseTooLargeDescription() {
    // Use a value with no digit grouping so locale doesn't affect the check.
    let error = GalleryServiceError.responseTooLarge(limit: 999)
    #expect(error.errorDescription?.contains("999") ?? false)
  }

  @Test func hashMismatchDescription() {
    let error = GalleryServiceError.hashMismatch(expected: "abc", actual: "def")
    #expect(error.errorDescription?.contains("abc") ?? false)
    #expect(error.errorDescription?.contains("def") ?? false)
  }

  @Test func invalidResponseDescription() {
    let error = GalleryServiceError.invalidResponse
    #expect(error.errorDescription?.contains("malformed") ?? false)
  }

  @Test func unexpectedStatusDescription() {
    let error = GalleryServiceError.unexpectedStatus(500)
    #expect(error.errorDescription?.contains("500") ?? false)
  }

  @Test func corruptedCacheDescription() {
    let error = GalleryServiceError.corruptedCache
    #expect(error.errorDescription?.contains("corrupt") ?? false)
  }
}
