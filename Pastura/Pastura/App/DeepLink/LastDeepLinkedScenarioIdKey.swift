import SwiftUI

/// Environment key carrying the scenario id most recently opened via
/// Deep Link for the current scene. `GalleryScenarioDetailView` reads
/// this to decide whether to render a "Opened from external link"
/// banner. The key is scoped to `RootView` and reset on pop-to-root so
/// the banner doesn't falsely appear when the user revisits the same
/// scenario through Share Board.
///
/// The value is `Optional<String>` rather than a richer "source" enum
/// because navigation state lives on `AppRouter.Route` and must stay
/// navigation-only (see `.claude/rules/navigation.md`). Source
/// attribution is side-channel UI state propagated via this key.
private struct LastDeepLinkedScenarioIdKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

extension EnvironmentValues {
  var lastDeepLinkedScenarioId: String? {
    get { self[LastDeepLinkedScenarioIdKey.self] }
    set { self[LastDeepLinkedScenarioIdKey.self] = newValue }
  }
}
