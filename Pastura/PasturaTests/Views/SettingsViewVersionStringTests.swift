import Testing

@testable import Pastura

/// Pins `SettingsView.versionString(from:)` — the pure formatter behind the
/// About section's version row (ADR-023 §6 S5-3 H7 prerequisite). Parameterized
/// over an injected info dictionary rather than `Bundle.main` per
/// `.claude/rules/view-testing.md` § "Extract View logic to unit tests", since
/// `Bundle.main` in the test process is the test runner's bundle, not the app's.
@Suite(.timeLimit(.minutes(1)))
struct SettingsViewVersionStringTests {
  @Test("formats short version and build number")
  func formatsBothFields() {
    let info: [String: Any] = [
      "CFBundleShortVersionString": "1.2",
      "CFBundleVersion": "826"
    ]
    #expect(SettingsView.versionString(from: info) == "1.2 (826)")
  }

  @Test("falls back to \"?\" for a missing short version, no force unwrap")
  func fallsBackForMissingShortVersion() {
    let info: [String: Any] = ["CFBundleVersion": "826"]
    #expect(SettingsView.versionString(from: info) == "? (826)")
  }

  @Test("falls back to \"?\" for a missing build number")
  func fallsBackForMissingBuildNumber() {
    let info: [String: Any] = ["CFBundleShortVersionString": "1.2"]
    #expect(SettingsView.versionString(from: info) == "1.2 (?)")
  }

  @Test("falls back to \"? (?)\" for a nil info dictionary")
  func fallsBackForNilDictionary() {
    #expect(SettingsView.versionString(from: nil) == "? (?)")
  }
}
