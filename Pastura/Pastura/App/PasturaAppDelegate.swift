import SwiftUI
import UIKit

/// `UIApplicationDelegate` adaptor for the SwiftUI app. PR2 adds this solely
/// to receive `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
/// — SwiftUI's `App` protocol doesn't expose this callback.
///
/// ## Flow
///
/// When iOS relaunches the app to deliver background URLSession completion
/// events (with `sessionSendsLaunchEvents = true`), it calls
/// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
/// BEFORE the recreated `URLSession` replays any events. We stash the
/// completion handler on `URLSessionModelDownloader.shared`; the delegate's
/// `urlSessionDidFinishEvents(forBackgroundURLSession:)` callback later
/// extracts it and dispatches to the main queue, satisfying Apple's "handler
/// must run on main" contract.
///
/// Foreground launches never invoke this method — the handler slot stays
/// `nil` and the delegate's `urlSessionDidFinishEvents` firing (if any) is a
/// no-op.
@MainActor
final class PasturaAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    Self.configureNavigationBarTitleColor()
    return true
  }

  /// Tints navigation-bar titles (large + inline) with `Color.ink`
  /// (#2D2E26) process-wide via the `UINavigationBar` appearance proxy.
  ///
  /// ## Why global, why here
  ///
  /// SwiftUI exposes no per-`NavigationStack` title-color modifier that
  /// preserves the system large→inline scroll-collapse, so the title
  /// color is set once through the UIKit appearance proxy. The browse
  /// screens otherwise render system-default near-black (`label`) titles
  /// that read cold on the warm `screenBackground` field (design-system
  /// §1 / §2.2). This is the title half of the ink migration; body text
  /// is tinted at each View.
  ///
  /// Backgrounds mirror the iOS default so the visual bar behavior is
  /// unchanged: transparent at the scroll edge (large-title resting
  /// state), system blur when scrolled (`standard` / `compact`). Only the
  /// title foreground color is overridden.
  ///
  /// The proxy is global, so sheet-owned `NavigationStack`s inherit the
  /// ink title too — intended (ink titles are wanted app-wide); verified
  /// by manual QA on PhaseEditorSheet / PersonaEditorSheet / ScoreboardSheet
  /// / ModelDownloadView.
  static func configureNavigationBarTitleColor() {
    let ink = UIColor(Color.ink)
    let titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: ink]

    let opaque = UINavigationBarAppearance()
    opaque.configureWithDefaultBackground()
    opaque.titleTextAttributes = titleAttributes
    opaque.largeTitleTextAttributes = titleAttributes

    let transparent = UINavigationBarAppearance()
    transparent.configureWithTransparentBackground()
    transparent.titleTextAttributes = titleAttributes
    transparent.largeTitleTextAttributes = titleAttributes

    let proxy = UINavigationBar.appearance()
    proxy.standardAppearance = opaque
    proxy.compactAppearance = opaque
    proxy.scrollEdgeAppearance = transparent
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    // Defensive guard: only handle the URLSession we own. A different
    // identifier here would mean another library registered for BG events;
    // call the handler immediately so iOS can return to its idle state.
    guard identifier == URLSessionModelDownloader.backgroundSessionIdentifier else {
      completionHandler()
      return
    }
    // Bridge the UIKit-supplied `() -> Void` to the `@Sendable`-typed slot.
    // UIKit's `completionHandler` parameter has no `@Sendable` annotation, so
    // Swift 6 strict concurrency rejects capturing it directly inside a
    // `@Sendable` closure. `nonisolated(unsafe)` is the documented escape
    // valve for system-supplied closures we know to be safe across executor
    // hops — Apple's contract guarantees this handler is safe to invoke from
    // any thread, and `URLSessionModelDownloader.urlSessionDidFinishEvents`
    // routes the invocation to the main queue per the BG-session contract.
    nonisolated(unsafe) let handler = completionHandler
    URLSessionModelDownloader.shared.setBackgroundCompletionHandler { @Sendable in
      handler()
    }
  }
}
