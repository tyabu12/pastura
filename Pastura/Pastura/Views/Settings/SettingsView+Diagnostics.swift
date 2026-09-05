import SwiftUI

// About section (app name + version, hosting the hidden H7-probe-reveal
// gesture) and the Diagnostics section (ADR-023 §6 S5-3 H7) for
// `SettingsView`. Split into this sibling to keep `SettingsView` under the
// file_length cap. `SettingsView` is a default-MainActor View, so this
// extension needs no `nonisolated` annotation.
//
// Sunset (ADR-023 §6 S5-5): the Diagnostics section, its state
// (`isH7ProbeRevealed`, `versionTapCount`, `isShowingH7CrashConfirm`,
// `isSharedEngineEnabled`), `FeatureFlags.h7CrashProbeEnabled`,
// `FeatureFlags.sharedEngineEnabled` (the S5-4 engine switch, whose default
// flips at S5-5), `SharedEngineDiagnostics`,
// and `H7CrashTrigger` are deleted together with the Kotlin `H7CrashProbe`.
// The About section and its version row stay — the 5-tap gesture host is
// removed, not the row itself.

extension SettingsView {
  /// App-identity row: name + version, e.g. "Pastura" / "1.2 (826)". Also
  /// hosts the hidden 5-tap reveal gesture for the Diagnostics section
  /// (TestFlight users have no shell to run `defaults write` from, so this
  /// is the only flip path there) — the tap counter itself only exists on a
  /// `isSandboxOrDebug` build, so an App Store install carries no gesture at
  /// all, not merely a no-op one.
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
      .modifier(
        H7RevealGestureModifier(
          channelHint: isSandboxOrDebug,
          tapCount: $versionTapCount,
          revealed: $isH7ProbeRevealed
        )
      )
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

  /// One Kotlin-rendered validation message for the S5-4 acceptance row.
  ///
  /// Forwards to `SharedEngineDiagnostics` under `App/KMP/` rather than
  /// importing `PasturaSharedEngine` here: CLAUDE.md § Dependency Rules allows
  /// the umbrella to be imported from `App/` only, never from `Views/`.
  ///
  /// Not `private`: `private` is file-scoped and this is read from
  /// ``diagnosticsSection`` below — which is in the same file today, but the
  /// section is the thing that moves at S5-5, not this.
  static var sharedEngineSampleMessage: String {
    SharedEngineDiagnostics.sampleRenderedMessage()
  }

  /// H7 crash-probe section (ADR-023 §6 S5-3, ADR-004 §9.2). Rendered only
  /// once both the channel hint and the explicit opt-in flag are true — see
  /// `BuildChannel`'s type-level doc for why the channel hint alone is never
  /// a sufficient gate.
  ///
  /// Not `private`: `private` is file-scoped, and `SettingsView.body` lives
  /// in the sibling file.
  @ViewBuilder
  var diagnosticsSection: some View {
    if isSandboxOrDebug && isH7ProbeRevealed {
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
              .foregroundStyle(Color.muted)
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
              Self.sharedEngineSampleMessage
            )
          )
          .font(.caption)
          .foregroundStyle(Color.inkSecondary)
          .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
          .accessibilityIdentifier("settings.sharedEngineSampleMessage")

          Text(
            String(
              localized:
                "This crashes the app on purpose, to verify crash reporting works for the shared engine."
            )
          )
          .font(.caption)
          .foregroundStyle(Color.inkSecondary)
          .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)

          Button {
            isShowingH7CrashConfirm = true
          } label: {
            HStack {
              Text(String(localized: "Crash the shared engine"))
                .foregroundStyle(Color.danger)
              Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
          }
          .accessibilityIdentifier("settings.h7CrashButton")
        }
        .padding(.vertical, 8)
      }
    }
  }

}

/// Counts taps on the version row and reveals the Diagnostics section on
/// the 5th, but only when the build channel hint is true — the counter
/// itself must not exist on an App Store build path, not merely no-op, so
/// the gate wraps the gesture rather than sitting inside the tap handler.
/// The hint is passed in (resolved once by `SettingsView`'s `.task`) because
/// `BuildChannel` is async under StoreKit 2.
private struct H7RevealGestureModifier: ViewModifier {
  let channelHint: Bool
  @Binding var tapCount: Int
  @Binding var revealed: Bool

  func body(content: Content) -> some View {
    if channelHint {
      content.onTapGesture {
        tapCount += 1
        // Exactly the fifth tap: later taps must not keep re-writing the key.
        if tapCount == 5 {
          FeatureFlags.setH7CrashProbeEnabled(true)
          revealed = true
        }
      }
    } else {
      content
    }
  }
}

/// Extracted `ViewModifier` (mirrors `ClearAllConfirmationModifier`) for the
/// H7 crash-confirmation alert. `.alert` (not `.confirmationDialog`) for the
/// same iOS 26 popover-anchor reason as the model-delete confirmation (the
/// `pendingDelete` alert in `SettingsView.body`) — but deliberately without
/// that block's `#if !targetEnvironment(simulator)` wrapper: that guard is
/// model-deletion-specific (device-only model lifecycle), while the
/// Diagnostics button is reachable on the simulator too. Not `private` —
/// attached from `SettingsView.body` in the sibling file.
///
/// The alert — and with it the only call site of `H7CrashTrigger.fire()` —
/// is attached only behind the channel gate, by the same mechanism as the
/// reveal gesture: an App Store build path carries no crash call site at all,
/// not merely an unreachable one.
struct H7CrashConfirmationModifier: ViewModifier {
  let channelHint: Bool
  @Binding var isPresented: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if channelHint {
      gated(content)
    } else {
      content
    }
  }

  private func gated(_ content: Content) -> some View {
    content
      .alert(
        String(localized: "Crash the app now?"),
        isPresented: $isPresented
      ) {
        Button(String(localized: "Crash"), role: .destructive) {
          H7CrashTrigger.fire()
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      }
  }
}
