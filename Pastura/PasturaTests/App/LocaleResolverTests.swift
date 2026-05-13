import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct LocaleResolverTests {

  @Test func jaLocaleReturnsJa() {
    let result = LocaleResolver.deviceDefault(preferredLocalizations: ["ja"])
    #expect(result == "ja")
  }

  @Test func enLocaleReturnsEn() {
    let result = LocaleResolver.deviceDefault(preferredLocalizations: ["en"])
    #expect(result == "en")
  }

  @Test func unsupportedLocaleReturnsEn() {
    let result = LocaleResolver.deviceDefault(preferredLocalizations: ["fr"])
    #expect(result == "en")
  }

  @Test func emptyLocaleReturnsEn() {
    let result = LocaleResolver.deviceDefault(preferredLocalizations: [])
    #expect(result == "en")
  }
}
