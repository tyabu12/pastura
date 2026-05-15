import Foundation
import Testing

@testable import Pastura

/// Pins the UI-shell-locale routing of the Settings → Privacy Policy
/// external link (#396). Per ADR-010 D6 (UI shell consumer), routing
/// reads `Bundle.main.preferredLocalizations` directly — `LocaleResolver`
/// is deliberately not used here (its D2 scope is new-data creation +
/// multi-variant selection, not external URL routing). The `ja` page
/// mirrors at `pages/ja/legal/privacy-policy/`; every other locale
/// falls through to the English page.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SettingsViewLocalizedURLTests {

  @Test func jaLocaleResolvesToJapanesePage() {
    let url = localizedPrivacyPolicyURL(preferredLocalizations: ["ja"])
    #expect(url?.absoluteString == "https://pastura.app/ja/legal/privacy-policy/")
  }

  @Test func enLocaleResolvesToEnglishPage() {
    let url = localizedPrivacyPolicyURL(preferredLocalizations: ["en"])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }

  @Test func unsupportedLocaleFallsBackToEnglishPage() {
    let url = localizedPrivacyPolicyURL(preferredLocalizations: ["fr"])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }

  @Test func emptyPreferredLocalizationsFallsBackToEnglishPage() {
    let url = localizedPrivacyPolicyURL(preferredLocalizations: [])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }
}
