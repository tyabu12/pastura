import SwiftUI

/// Environment flag mirroring ``UITestMode/isActive``, injected once at the
/// `RootView`/`WindowGroup` boundary (see `PasturaApp`). Leaf Views read it via
/// `@Environment(\.isUITestMode)` to drop continuous animations under the
/// XCUITest harness — centralizing the single `--ui-test` read rather than
/// scattering `CommandLine.arguments` lookups across the View tree (#728).
///
/// Defaults to `false`, so Previews and any View rendered without the root
/// injection behave exactly as production.
private struct UITestModeKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var isUITestMode: Bool {
    get { self[UITestModeKey.self] }
    set { self[UITestModeKey.self] = newValue }
  }
}
