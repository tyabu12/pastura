import SwiftUI

/// Pastura's flat back chevron, replacing the iOS-26 Liquid Glass system
/// back button on root-stack pushed views. SF Symbol `chevron.backward`
/// tinted via `Color.ink`; tap routes through ``AppRouter/pop()``.
///
/// ## Why custom
///
/// On iOS 26, the system back button on a `NavigationStack`-pushed view
/// renders inside a translucent "Liquid Glass" capsule. The capsule
/// styling clashes with Pastura's flat / moss / frosted aesthetic
/// (see `docs/design/design-system.md` §1). This component renders a
/// plain chevron with no capsule, opting out via `.buttonStyle(.plain)`.
///
/// ## Usage
///
/// Apply on every root-stack pushed view that participates in
/// `HomeView.routeDestination(_:)`:
///
/// ```swift
/// .navigationBarBackButtonHidden(true)
/// .toolbar {
///   ToolbarItem(placement: .topBarLeading) { PasturaBackButton() }
/// }
/// ```
///
/// **Root-stack only.** This view calls `router.pop()` which mutates
/// `AppRouter.path`. For sheet / fullScreenCover dismissal, use
/// `@Environment(\.dismiss)` directly — `PasturaBackButton` will NOT
/// dismiss a sheet. See `.claude/rules/navigation.md`.
///
/// ## Accessibility
///
/// Announces as `"Back, button"`. The chevron-only design intentionally
/// omits the upstream view title that the system back button would
/// normally append (e.g. `"Back, button, Pastura"`). This regression is
/// documented in `.claude/rules/navigation.md` QA scenario 2.
///
/// ## Swipe-back gesture
///
/// `.navigationBarBackButtonHidden(true)` hides the back BUTTON only —
/// the bar itself stays in the layout, so iOS keeps the
/// `interactivePopGestureRecognizer` enabled. (Contrast with
/// `.toolbar(.hidden, for: .navigationBar)` which triggers FB13484530
/// on iOS 17.x and disables the gesture — see memory
/// `reference_swiftui_toolbar_hide_apis.md`.)
struct PasturaBackButton: View {
  @Environment(AppRouter.self) private var router

  var body: some View {
    Button {
      router.pop()
    } label: {
      Image(systemName: Self.iconName)
        .foregroundStyle(Self.tint)
    }
    // `.plain` opts out of iOS 26's automatic Liquid Glass treatment
    // for ToolbarItem buttons. Without this, iOS 26 wraps custom
    // toolbar buttons in a glass capsule that defeats the purpose
    // of the custom styling.
    .buttonStyle(.plain)
    .accessibilityLabel(Self.accessibilityLabel)
    .accessibilityIdentifier("pasturaBackButton")
  }

  /// SF Symbol name. `chevron.backward` (RTL-aware) over `chevron.left`
  /// per Apple HIG — the back affordance flips with reading direction.
  static let iconName = "chevron.backward"

  /// Foreground tint. `Color.ink` (#2D2E26) keeps the chevron flat and
  /// neutral, in line with design-system §2.2. Returning the concrete
  /// `Color` (not a bare ShapeStyle) avoids the silent-fail of
  /// `.foregroundStyle(.ink)` for Color-extension tokens — see memory
  /// `feedback_shapestyle_color_token_trap.md`.
  static let tint: Color = Color.ink

  /// Localized accessibility label. Chevron-only by design — see the
  /// type doc-comment for the upstream-title regression rationale.
  static let accessibilityLabel: String = String(localized: "Back")
}

/// Flat button style for toolbar action items, opting out of iOS 26's
/// Liquid Glass capsule treatment that `ToolbarItem` placement otherwise
/// applies automatically (`.confirmationAction` → `glassProminent`,
/// `.destructiveAction` → `glassProminent` with role tint, etc.).
///
/// Three variants map to design-system §2 tokens:
///
/// - `.primary` — `Color.mossDark` (#6B7852). Save / confirm. Pastura's
///   only brand-accent color (§2.3).
/// - `.destructive` — `Color.dangerInk` (#6F4540). Delete / discard. The
///   ink-strength token (not the soft `Color.danger`) so the button
///   reads as the destructive intent without screaming red.
/// - `.secondary` — `Color.ink` (#2D2E26). Share / Film / More. Neutral
///   ink for non-primary actions.
///
/// ## Usage
///
/// ```swift
/// ToolbarItem(placement: .primaryAction) {
///   Button("Save") { ... }
///     .buttonStyle(PasturaToolbarButtonStyle(variant: .primary))
/// }
/// ```
///
/// Pressed state dims the foreground to `pressedOpacity`; no capsule
/// background, no scale animation — keeping with design-system §1's
/// "static, observed" voice.
struct PasturaToolbarButtonStyle: ButtonStyle {

  /// Visual role. The variant chosen at the callsite encodes the
  /// action's intent — Save vs. Delete vs. Share — via color rather
  /// than iOS's role-based glass tinting.
  enum Variant: Sendable {
    case primary
    case destructive
    case secondary
  }

  let variant: Variant

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Self.foreground(for: variant))
      .opacity(configuration.isPressed ? Self.pressedOpacity : 1.0)
  }

  /// Variant → color mapping. Extracted as a static helper so unit tests
  /// can pin the contract without rendering a SwiftUI body (ADR-009).
  static func foreground(for variant: Variant) -> Color {
    switch variant {
    case .primary: return Color.mossDark
    case .destructive: return Color.dangerInk
    case .secondary: return Color.ink
    }
  }

  /// Pressed-state opacity reduction. Single source of truth so a
  /// future refactor can tune the press feedback in one place.
  /// `0.6` keeps the chevron / label clearly visible while signalling
  /// the touch.
  static let pressedOpacity: Double = 0.6
}
