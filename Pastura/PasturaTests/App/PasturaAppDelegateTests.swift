import SwiftUI
import Testing
import UIKit

@testable import Pastura

/// Pins the global navigation-bar title tint (the title half of the ink
/// migration). The appearance proxy is process-global mutable state, so
/// this test deliberately sets it and asserts the foreground color —
/// other suites don't assert the default appearance, so the mutation is
/// inert for them.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PasturaAppDelegateTests {

  @Test func configuresInkNavigationTitleColor() {
    PasturaAppDelegate.configureNavigationBarTitleColor()

    let proxy = UINavigationBar.appearance()
    let standardTitle =
      proxy.standardAppearance.titleTextAttributes[.foregroundColor] as? UIColor
    let standardLarge =
      proxy.standardAppearance.largeTitleTextAttributes[.foregroundColor] as? UIColor
    let scrollEdgeLarge =
      proxy.scrollEdgeAppearance?.largeTitleTextAttributes[.foregroundColor] as? UIColor

    #expect(standardTitle == UIColor(Color.ink))
    #expect(standardLarge == UIColor(Color.ink))
    #expect(scrollEdgeLarge == UIColor(Color.ink))
  }
}
