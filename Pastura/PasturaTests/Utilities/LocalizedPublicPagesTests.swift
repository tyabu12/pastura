import Foundation
import Testing

@testable import Pastura

/// Pins the UI-shell-locale routing of external links to Pastura's
/// public pages (#396 privacy policy, #499 support). Per ADR-010 D6
/// (UI shell consumer), routing reads `Bundle.main.preferredLocalizations`
/// directly — `LocaleResolver` is deliberately not used (its D2 scope is
/// new-data creation + multi-variant selection, not external URL
/// routing). The `ja` pages mirror at `web/src/pages/ja/**`; every other locale
/// falls through to the English pages.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocalizedPublicPagesTests {

  // MARK: - Privacy policy

  @Test func jaLocaleResolvesToJapanesePrivacyPolicy() {
    let url = LocalizedPublicPages.privacyPolicy(preferredLocalizations: ["ja"])
    #expect(url?.absoluteString == "https://pastura.app/ja/legal/privacy-policy/")
  }

  @Test func enLocaleResolvesToEnglishPrivacyPolicy() {
    let url = LocalizedPublicPages.privacyPolicy(preferredLocalizations: ["en"])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }

  @Test func unsupportedLocaleFallsBackToEnglishPrivacyPolicy() {
    let url = LocalizedPublicPages.privacyPolicy(preferredLocalizations: ["fr"])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }

  @Test func emptyPreferredLocalizationsFallsBackToEnglishPrivacyPolicy() {
    let url = LocalizedPublicPages.privacyPolicy(preferredLocalizations: [])
    #expect(url?.absoluteString == "https://pastura.app/legal/privacy-policy/")
  }

  // MARK: - Support

  @Test func jaLocaleResolvesToJapaneseSupportPage() {
    let url = LocalizedPublicPages.support(preferredLocalizations: ["ja"])
    #expect(url?.absoluteString == "https://pastura.app/ja/support/")
  }

  @Test func enLocaleResolvesToEnglishSupportPage() {
    let url = LocalizedPublicPages.support(preferredLocalizations: ["en"])
    #expect(url?.absoluteString == "https://pastura.app/support/")
  }

  @Test func unsupportedLocaleFallsBackToEnglishSupportPage() {
    let url = LocalizedPublicPages.support(preferredLocalizations: ["de"])
    #expect(url?.absoluteString == "https://pastura.app/support/")
  }

  // MARK: - Scenario guide

  @Test func jaLocaleResolvesToJapaneseScenarioGuide() {
    let url = LocalizedPublicPages.scenarioGuide(preferredLocalizations: ["ja"])
    #expect(url?.absoluteString == "https://pastura.app/ja/docs/scenario/")
  }

  @Test func enLocaleResolvesToEnglishScenarioGuide() {
    let url = LocalizedPublicPages.scenarioGuide(preferredLocalizations: ["en"])
    #expect(url?.absoluteString == "https://pastura.app/docs/scenario/")
  }

  @Test func unsupportedLocaleFallsBackToEnglishScenarioGuide() {
    let url = LocalizedPublicPages.scenarioGuide(preferredLocalizations: ["es"])
    #expect(url?.absoluteString == "https://pastura.app/docs/scenario/")
  }

  @Test func emptyPreferredLocalizationsFallsBackToEnglishScenarioGuide() {
    let url = LocalizedPublicPages.scenarioGuide(preferredLocalizations: [])
    #expect(url?.absoluteString == "https://pastura.app/docs/scenario/")
  }

  // MARK: - Supported devices anchor

  @Test func jaLocaleResolvesToJapaneseSupportedDevicesAnchor() {
    let url = LocalizedPublicPages.supportedDevices(preferredLocalizations: ["ja"])
    #expect(url?.absoluteString == "https://pastura.app/ja/support/#supported-devices")
  }

  @Test func enLocaleResolvesToEnglishSupportedDevicesAnchor() {
    let url = LocalizedPublicPages.supportedDevices(preferredLocalizations: ["en"])
    #expect(url?.absoluteString == "https://pastura.app/support/#supported-devices")
  }
}
