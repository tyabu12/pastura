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
    // Byte count is formatted via ByteCountFormatter (locale-aware,
    // human-friendly units), so assert the locale-invariant literal
    // fragment rather than the numeric output.
    let error = GalleryServiceError.responseTooLarge(limit: 1_500_000)
    #expect(error.errorDescription?.contains("size limit") ?? false)
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
