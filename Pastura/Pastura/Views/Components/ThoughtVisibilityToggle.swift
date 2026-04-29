import SwiftUI

/// A toggle button that controls "show all thoughts" mode in chat-stream
/// views (Simulation / Results / DL-time demo). On state uses the filled
/// eye icon + moss accent; off state uses the slashed eye icon + muted
/// ink. Caller provides `font` via `.font(...)` on the toggle if they
/// want sizing larger than system default.
///
/// Used by `SimulationView`, `ResultDetailView`, and
/// `ModelDownloadHostView` — see issue #273.
struct ThoughtVisibilityToggle: View {
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Image(systemName: Self.iconName(for: isOn))
        .foregroundStyle(Self.tint(for: isOn))
    }
    .accessibilityLabel(Self.accessibilityLabel(for: isOn))
  }

  /// Filled eye for the "showing thoughts" state, slashed eye for
  /// "hidden". Switched from `text.bubble.fill` / `text.bubble` in
  /// #273 PR 2 — real-device QA after PR 1a found the eye family
  /// communicates the show / hide affordance more directly than the
  /// chat-bubble outline. Pinned by
  /// `ThoughtVisibilityToggleContractTests` to catch accidental swaps.
  static func iconName(for isOn: Bool) -> String {
    isOn ? "eye.fill" : "eye.slash"
  }

  /// `Color.moss` (accent) for ON, `Color.inkSecondary` (neutral muted)
  /// for OFF. Returning a concrete `Color` (not the bare `.moss` ShapeStyle
  /// shorthand) is intentional — see memory `feedback_shapestyle_color_token_trap.md`:
  /// `.foregroundStyle(.muted)` silently fails for Color extension tokens.
  static func tint(for isOn: Bool) -> Color {
    isOn ? Color.moss : Color.inkSecondary
  }

  /// Localized accessibility label that flips between "Hide all thoughts"
  /// (when ON) and "Show all thoughts" (when OFF). The verb pivots on
  /// what tap-action is available next.
  static func accessibilityLabel(for isOn: Bool) -> String {
    isOn
      ? String(localized: "Hide all thoughts")
      : String(localized: "Show all thoughts")
  }
}

#Preview {
  struct Wrapper: View {
    @State private var isOn = true
    var body: some View {
      VStack(spacing: 16) {
        ThoughtVisibilityToggle(isOn: $isOn).font(.title3)
        Text("isOn: \(String(isOn))")
      }
    }
  }
  return Wrapper()
}
