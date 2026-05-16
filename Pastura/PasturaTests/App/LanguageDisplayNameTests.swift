import Foundation
import Testing

@testable import Pastura

/// Coverage for the locale-aware ISO 639-1 code → display name resolver.
/// Verifies the helper does not leak raw codes ("ja" / "en") into user-
/// facing toast copy for ADR-010's `.languageMismatch` UI surface.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct LanguageDisplayNameTests {
  @Test func japaneseCodeResolvesToLocalizedName() {
    let name = LanguageDisplayName.resolve("ja")
    #expect(!name.isEmpty)
    #expect(name != "ja", "Display name must not leak the raw ISO code")
  }

  @Test func englishCodeResolvesToLocalizedName() {
    let name = LanguageDisplayName.resolve("en")
    #expect(!name.isEmpty)
    #expect(name != "en", "Display name must not leak the raw ISO code")
  }

  @Test func unknownCodeResolvesToFallback() {
    let name = LanguageDisplayName.resolve("xx")
    #expect(!name.isEmpty)
    #expect(name != "xx", "Unknown code must not pass through as the raw token")
  }
}
