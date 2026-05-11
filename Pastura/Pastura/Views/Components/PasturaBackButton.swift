import SwiftUI
import UIKit

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
/// ## Swipe-back gesture (UIKit bridging)
///
/// On iOS 26, `.navigationBarBackButtonHidden(true)` disables the
/// `interactivePopGestureRecognizer` (verified by `BackGestureTests` —
/// hiding the back button alone breaks edge-pan even though the bar
/// stays in the layout). The button mounts an invisible
/// `UIViewControllerRepresentable` probe that walks the parent chain
/// to the host `UINavigationController` and reinstalls the gesture
/// with a delegate gating on `viewControllers.count > 1`, preserving
/// the swipe-back affordance without re-enabling pop on the root.
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

// MARK: - Toolbar shared-background opt-out (iOS 26+)

extension ToolbarContent {
  /// Hide the iOS 26 Liquid Glass shared background that the system
  /// applies to toolbar items by default. No-op on iOS < 26 where the
  /// `sharedBackgroundVisibility(_:)` API doesn't exist.
  ///
  /// `.buttonStyle(.plain)` on the inner `Button` alone does NOT
  /// remove the capsule that wraps every `ToolbarItem` on iOS 26 —
  /// the wrapping happens at the toolbar level, not the button level.
  /// This modifier is the documented opt-out mechanism (Apple Dev Docs,
  /// WWDC25). Real-device verified on iPhone 16e (iOS 26.4.2) — the
  /// chevron renders flat against the bar background, no capsule.
  ///
  /// Apply to every `ToolbarItem` that wraps a custom Pastura control
  /// (`PasturaBackButton`, action items styled with
  /// `PasturaToolbarButtonStyle`).
  @ToolbarContentBuilder
  func hidingPasturaSharedBackground() -> some ToolbarContent {
    if #available(iOS 26.0, *) {
      self.sharedBackgroundVisibility(.hidden)
    } else {
      self
    }
  }
}

// MARK: - View-level swipe-back preservation

extension View {
  /// Apply on every root-stack pushed view that uses
  /// `.navigationBarBackButtonHidden(true)` + ``PasturaBackButton``.
  ///
  /// On iOS 26, hiding the back button via
  /// `.navigationBarBackButtonHidden` disables the
  /// `interactivePopGestureRecognizer` (verified by `BackGestureTests`).
  /// This modifier mounts an invisible `UIViewControllerRepresentable`
  /// probe at the view level (where the SwiftUI hosting controller
  /// reliably has a `UINavigationController` ancestor) and reinstalls
  /// the gesture with a delegate gating on
  /// `viewControllers.count > 1` — preserving swipe-back on pushed
  /// views without re-enabling pop on the root.
  ///
  /// The toolbar slot is too constrained to host the probe (zero-size
  /// background views in `ToolbarItem` may not be mounted), hence the
  /// view-level placement.
  func preservesPasturaSwipeBackGesture() -> some View {
    background(SwipeBackGestureProbe().allowsHitTesting(false))
  }
}

// MARK: - UIKit bridge for swipe-back gesture preservation

/// Invisible probe that walks the parent chain to the host
/// `UINavigationController` and reinstalls the
/// `interactivePopGestureRecognizer` after
/// `.navigationBarBackButtonHidden(true)` disables it on iOS 26.
///
/// Lifetime is tied to ``PasturaBackButton``'s view tree, so the
/// gesture restoration applies exactly while the back button is
/// mounted (i.e., while the pushed view is on screen). On pop, the
/// probe deallocates and its `SwipeBackGestureDelegate` (held by the
/// VC) deallocates with it; the recognizer's `weak delegate` becomes
/// nil and iOS reverts to default gating.
private struct SwipeBackGestureProbe: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> SwipeBackProbeViewController {
    SwipeBackProbeViewController()
  }

  func updateUIViewController(
    _ uiViewController: SwipeBackProbeViewController, context: Context
  ) {}
}

/// Hosting `UIViewController` for ``SwipeBackGestureProbe``. Walks up
/// the parent chain on `didMove(toParent:)` to find the
/// `UINavigationController` and installs a delegate that gates the
/// gesture on `viewControllers.count > 1` (so swipe-back works on
/// pushed views but stays inert on the root, matching iOS default).
private final class SwipeBackProbeViewController: UIViewController {
  private var gestureDelegate: SwipeBackGestureDelegate?

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    installGestureDelegate()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Re-install on viewDidAppear in case SwiftUI applies
    // `.navigationBarBackButtonHidden` after our `didMove` ran — without
    // this, the recognizer disable can win the race against our enable.
    installGestureDelegate()
  }

  private func installGestureDelegate() {
    let nav: UINavigationController? =
      Self.findNavigationController(starting: parent)
      ?? Self.findNavigationController(in: view.window?.rootViewController)
    guard let nav else { return }
    let delegate = SwipeBackGestureDelegate()
    delegate.navigationController = nav
    self.gestureDelegate = delegate
    nav.interactivePopGestureRecognizer?.isEnabled = true
    nav.interactivePopGestureRecognizer?.delegate = delegate
  }

  private static func findNavigationController(
    starting startingViewController: UIViewController?
  ) -> UINavigationController? {
    var current = startingViewController
    while let view = current {
      if let nav = view as? UINavigationController { return nav }
      if let nav = view.navigationController { return nav }
      current = view.parent
    }
    return nil
  }

  /// Recursive descent from window root — covers the case where
  /// SwiftUI's NavigationStack hosts its UINavigationController
  /// outside the probe's parent chain.
  private static func findNavigationController(
    in viewController: UIViewController?
  ) -> UINavigationController? {
    guard let viewController else { return nil }
    if let nav = viewController as? UINavigationController { return nav }
    if let presented = viewController.presentedViewController,
      let nav = findNavigationController(in: presented) {
      return nav
    }
    for child in viewController.children {
      if let nav = findNavigationController(in: child) { return nav }
    }
    return nil
  }
}

/// Gesture-recognizer delegate that allows the interactive pop gesture
/// only when the host `UINavigationController` has more than one VC on
/// the stack (i.e., not on the root). Mirrors the default iOS gating
/// that `.navigationBarBackButtonHidden(true)` accidentally clobbers
/// on iOS 26.
private final class SwipeBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
  weak var navigationController: UINavigationController?

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    (navigationController?.viewControllers.count ?? 0) > 1
  }
}
