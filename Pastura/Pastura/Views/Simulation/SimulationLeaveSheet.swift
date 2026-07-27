import SwiftUI

/// Semantic color tokens for ``SimulationLeaveSheet``, extracted so
/// `SimulationControlsTokenTests` can pin them as a **change-detector
/// tripwire** (ADR-009 / view-testing.md
/// § "Change-detector tripwire for code-review-gated tokens").
///
/// The load-bearing decision: the "keep running" action is a *caution*
/// (design-system §2.6 `warning`, amber), **not** a *destructive* action
/// (§2.6 `danger`, red). The run keeps executing and is recoverable via the
/// in-flight indicator, so red would mis-signal data loss — including to
/// VoiceOver, which announces `.destructive` distinctly. The test guards that
/// `warning`-not-`danger` distinction against a silent token swap.
///
/// The button *layout* stays private to the sheet (`CautionButtonStyle` /
/// `NeutralButtonStyle`); only these semantic tokens are exposed for the test.
enum SimulationLeaveSheetTokens {
  /// Caution-action fill — `warningSoft` (#F2EAD3). Deliberately NOT `dangerSoft`.
  static let cautionFill: Color = .warningSoft

  /// Caution-action label — `warningInk` (#6F5C2D). Deliberately NOT `dangerInk`.
  static let cautionText: Color = .warningInk

  /// Caution-action hairline — `warning` (#C7A566).
  static let cautionBorder: Color = .warning

  /// Neutral cancel label — `inkSecondary`. Cancel stays neutral (§2.6).
  static let cancelText: Color = .inkSecondary

  /// Neutral cancel hairline — `rule`.
  static let cancelBorder: Color = .rule

  /// Corner radius, shared with `PasturaPrimaryButtonStyle` (12pt) so the
  /// three stacked buttons read as one family.
  static let cornerRadius: CGFloat = PasturaPrimaryButtonStyle.cornerRadius
}

/// Custom confirm-on-leave sheet for an in-flight simulation (#673 / #682).
///
/// Replaces the former system `.alert`, whose three buttons all rendered in
/// the green accent (no hierarchy). A bottom sheet lets each action carry a
/// semantic design-system color: a `mossDark` **primary** (the recommended,
/// fully-safe "pause and save"), a `warning`-amber **caution** ("keep
/// running" — recoverable, but the OS may terminate it while away), and a
/// neutral **cancel**. The caution uses §2.6 `warning`, NOT `danger` red,
/// because nothing is destroyed — see ``SimulationLeaveSheetTokens``.
///
/// Pastura's first custom confirm dialog: system `.alert` (the other ~13
/// sites) exposes no per-button color API (design-system §5.8.3). Presented
/// via `.sheet`, not `.confirmationDialog` (which mis-anchors as a popover on
/// iOS 26 — `.claude/rules/swiftui-traps.md`). Buttons wrap (`lineLimit(nil)`)
/// so long localized labels don't clip at large Dynamic Type sizes.
struct SimulationLeaveSheet: View {
  /// Persist a resumable `.paused`, then leave (recommended / safe).
  let onPauseAndLeave: () -> Void
  /// Park the run in memory and leave — it keeps executing in the background.
  let onKeepRunning: () -> Void
  /// Dismiss without leaving.
  let onStay: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Title + message come first so VoiceOver reads the context before the
      // action buttons.
      Text(String(localized: "A simulation is in progress"))
        .font(.headline)
        .multilineTextAlignment(.center)

      Text(
        String(
          localized:
            "Pause and save it so you can resume later, or keep it running while you step away?"
        )
      )
      .font(.subheadline)
      .foregroundStyle(Color.inkSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)

      VStack(spacing: 10) {
        Button(action: onPauseAndLeave) {
          sheetLabel(String(localized: "Pause and leave"))
        }
        .buttonStyle(PasturaPrimaryButtonStyle())

        Button(action: onKeepRunning) {
          sheetLabel(String(localized: "Leave & keep running"))
        }
        .buttonStyle(CautionButtonStyle())

        Button(action: onStay) {
          sheetLabel(String(localized: "Stay"))
        }
        .buttonStyle(NeutralButtonStyle())
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity)
  }

  /// Full-width, wrap-not-clip label shared by the three actions.
  private func sheetLabel(_ text: String) -> some View {
    Text(text)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .lineLimit(nil)
  }
}

/// Private — caution (amber) action style. Consumes the testable
/// ``SimulationLeaveSheetTokens`` so the warning-not-danger decision is
/// change-detector-pinned. Press feedback mirrors `PasturaPrimaryButtonStyle`
/// (opacity dim, no capsule / scale — §1 "static, observed").
private struct CautionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(SimulationLeaveSheetTokens.cautionText)
      .padding(.vertical, 15)
      .padding(.horizontal, 20)
      .background(
        SimulationLeaveSheetTokens.cautionFill,
        in: RoundedRectangle(
          cornerRadius: SimulationLeaveSheetTokens.cornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: SimulationLeaveSheetTokens.cornerRadius, style: .continuous)
          .strokeBorder(SimulationLeaveSheetTokens.cautionBorder, lineWidth: 1)
      )
      .opacity(configuration.isPressed ? PasturaPrimaryButtonStyle.pressedOpacity : 1.0)
  }
}

/// Private — neutral cancel ("Stay") style: transparent fill, `rule` hairline,
/// `inkSecondary` label (§2.6 "cancel stays neutral").
private struct NeutralButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(SimulationLeaveSheetTokens.cancelText)
      .padding(.vertical, 15)
      .padding(.horizontal, 20)
      .overlay(
        RoundedRectangle(cornerRadius: SimulationLeaveSheetTokens.cornerRadius, style: .continuous)
          .strokeBorder(SimulationLeaveSheetTokens.cancelBorder, lineWidth: 1)
      )
      .opacity(configuration.isPressed ? PasturaPrimaryButtonStyle.pressedOpacity : 1.0)
  }
}
