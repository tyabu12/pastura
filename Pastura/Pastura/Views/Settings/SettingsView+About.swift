import SwiftUI

// About section (app name + version) for `SettingsView`. Split into this
// sibling to keep `SettingsView` under the file_length cap. `SettingsView`
// is a default-MainActor View, so this extension needs no `nonisolated`
// annotation.
//
// The S5-4 Diagnostics section (the shared-engine opt-in Toggle and its
// sample-message row) was deleted in S5-5 now that the Kotlin engine is the
// sole fresh-run path — see ADR-023 §6. Only the About section remains.

extension SettingsView {
  /// App-identity row: name + version, e.g. "Pastura" / "1.2 (826)".
  ///
  /// Not `private`: `private` is file-scoped, and `SettingsView.body` lives
  /// in the sibling file.
  var aboutSection: some View {
    PasturaSection(String(localized: "About"), style: .grouped) {
      HStack {
        // "Pastura" is a brand name, never localized (HomeView.swift
        // precedent) — `Text(verbatim:)` keeps it from being flagged by the
        // i18n leak audit as an un-wrapped literal.
        Text(verbatim: "Pastura")
          .foregroundStyle(Color.ink)
        Spacer()
        Text(Self.appVersionString)
          .foregroundStyle(Color.inkSecondary)
      }
      .padding(.horizontal, 17)
      .padding(.vertical, 15)
      .contentShape(Rectangle())
      .accessibilityIdentifier("settings.versionRow")
    }
  }

  /// `"<short> (<build>)"` built from `CFBundleShortVersionString` /
  /// `CFBundleVersion`, `??`-falling back per field so a malformed bundle
  /// never force-unwraps (Hard Rule 1).
  static var appVersionString: String {
    versionString(from: Bundle.main.infoDictionary)
  }

  /// Pure formatting logic behind ``appVersionString``, taking the info
  /// dictionary as a parameter so it is unit-testable without depending on
  /// which bundle happens to be `Bundle.main` at test time
  /// (`.claude/rules/view-testing.md` § "Extract View logic to unit tests").
  static func versionString(from info: [String: Any]?) -> String {
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(short) (\(build))"
  }
}
