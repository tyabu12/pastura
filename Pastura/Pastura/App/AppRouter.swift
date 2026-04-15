import Foundation
import SwiftUI

/// Owner of the root `NavigationStack`'s path.
///
/// Inject via `@Environment(AppRouter.self)`. Bind the path with
/// `NavigationStack(path: $router.path)` at the root view, and call
/// `push(_:)` / `pop()` / `popToRoot()` from anywhere in the view tree
/// for programmatic navigation.
///
/// ## Scope (load-bearing)
///
/// `AppRouter` manages the **root NavigationStack's path only**. It is
/// deliberately not a place to put selection state, modal presentation
/// flags, search queries, or any other UI state. See
/// `.claude/rules/navigation.md` for the full convention.
///
/// Sheets, popovers, and `fullScreenCover`s have their own navigation
/// context and must use local `@State` — they are out of scope for this
/// router.
@Observable
@MainActor
final class AppRouter {
  /// Backing storage for `NavigationStack(path:)`.
  ///
  /// Typed as `[Route]` rather than `NavigationPath` because:
  /// 1. Pastura's destinations are a single `Route` enum — no
  ///    heterogeneous push needs.
  /// 2. A typed array is inspectable for tests and `pushIfOnTop`
  ///    style guards; `NavigationPath` is type-erased.
  /// 3. State restoration (NavigationPath's main strength via Codable)
  ///    is not currently required; `[Route]` is trivially Codable if
  ///    `Route` adopts Codable later.
  ///
  /// **Do not mutate this array directly from outside `AppRouter` and
  /// the root `NavigationStack` binding** — go through `push(_:)` /
  /// `pop()` / `popToRoot()` / `replacePath(_:)` so intent stays
  /// auditable. The property is `var` only because `NavigationStack`
  /// requires a `Binding`.
  var path: [Route] = []

  /// Pushes `route` onto the navigation path.
  func push(_ route: Route) {
    path.append(route)
  }

  /// Pushes `next` only when `expected` is the current top of the path.
  ///
  /// Use this after an `await`ed operation to avoid landing the user on
  /// an unrelated screen if the originating view was popped during the
  /// suspension. Concretely: a swipe-back gesture (or a programmatic
  /// `pop`) during the await removes the originating view from `path`;
  /// a raw `append` afterwards would push onto whatever is now on top.
  /// `pushIfOnTop` no-ops in that case. Returns `true` when the push
  /// happened.
  @discardableResult
  func pushIfOnTop(expected: Route, next: Route) -> Bool {
    guard path.last == expected else { return false }
    path.append(next)
    return true
  }

  /// Pops the most recent route, if any.
  func pop() {
    guard !path.isEmpty else { return }
    path.removeLast()
  }

  /// Pops back to the root view.
  func popToRoot() {
    path.removeAll()
  }

  /// Replaces the entire path. Reserved for future state-restoration /
  /// deep-link entry points; prefer `push` / `pop` from view code.
  func replacePath(_ routes: [Route]) {
    path = routes
  }
}
