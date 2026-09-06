import SwiftUI

// About section (app name + version) and the Diagnostics section for
// `SettingsView`. Split into this sibling to keep `SettingsView` under the
// file_length cap. `SettingsView` is a default-MainActor View, so this
// extension needs no `nonisolated` annotation.
//
// The S5-3 H7 crash probe (its reveal gesture, confirmation alert, and
// crash button) was deleted in S5-5 together with the Kotlin
// `H7CrashProbe`. The Diagnostics section is now gated solely on
// `isSandboxOrDebug`.
//
// Sunset (still pending, tracked separately from H7): `isSharedEngineEnabled`
// and its `.onChange` in `SettingsView`, `FeatureFlags.sharedEngineEnabled`
// (the S5-4 engine switch, whose default flips at S5-5), the Diagnostics
// section itself, `SharedEngineDiagnostics` + `SharedEngineDiagnosticsTests`
// (after which `SharedEngineRunner.renderedValidationMessage(for:)` can go
// back to `private`), and the three S5-4 catalog keys (`Run simulations on
// the shared engine`, `New runs use the Kotlin engine. …`, `Shared engine
// says: %@`). The About section and its version row stay.

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

  /// Diagnostics section (ADR-004 §9.2). Rendered only on a sandbox/debug
  /// build — see `BuildChannel`'s type-level doc for why the channel hint
  /// alone is never a sufficient gate for anything more sensitive than this.
  ///
  /// Not `private`: `private` is file-scoped, and `SettingsView.body` lives
  /// in the sibling file.
  @ViewBuilder
  var diagnosticsSection: some View {
    if isSandboxOrDebug {
      PasturaSection(String(localized: "Diagnostics"), style: .grouped) {
        VStack(alignment: .leading, spacing: 7) {
          // Label-closure form per the i18n convenience-init convention
          // (`.claude/rules/i18n-ui.md`).
          Toggle(isOn: $isSharedEngineEnabled) {
            VStack(alignment: .leading, spacing: 3) {
              Text(String(localized: "Run simulations on the shared engine"))
                .foregroundStyle(Color.ink)
              Text(
                String(
                  localized:
                    "New runs use the Kotlin engine. Resuming a paused run always uses the Swift engine."
                )
              )
              .font(.caption)
              .foregroundStyle(Color.inkSecondary)
            }
          }
          .tint(Color.link)
          .padding(.horizontal, 17)
          .padding(.vertical, 13)
          .accessibilityIdentifier("settings.sharedEngineToggle")

          // The S5-4 `ja` acceptance row: on a `ja` device this must render
          // the Kotlin-rendered message in Japanese
          // (`SharedEngineDiagnostics.sampleRenderedMessage()`'s doc comment
          // has the why).
          Text(
            String(
              format: String(localized: "Shared engine says: %@"),
              // Read through `App/KMP/` (cached there) rather than importing
              // `PasturaSharedEngine` here — the umbrella is `App/`-only
              // (CLAUDE.md § Dependency Rules).
              SharedEngineDiagnostics.cachedSampleRenderedMessage
            )
          )
          .font(.caption)
          .foregroundStyle(Color.inkSecondary)
          .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
          .accessibilityIdentifier("settings.sharedEngineSampleMessage")
        }
        .padding(.vertical, 8)
      }
    }
  }

}
