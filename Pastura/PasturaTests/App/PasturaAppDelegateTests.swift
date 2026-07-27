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

    // `UIColor` `==` on SwiftUI-derived colors compares representation,
    // not resolved RGBA — the equality holds here because both sides go
    // through the identical `UIColor(Color.ink)` conversion.
    //
    // ADR-028 fired this comment's own "built a different way" trigger:
    // `Color.ink` is now backed by a `UIColor(dynamicProvider:)` pair, not a
    // static sRGB `Color`. The pin still holds because both sides convert the
    // *same* `static let` instance, so representation equality survives — but
    // it is now resting on that, so a future change that resolves the alias on
    // either side (rather than passing the instance through) breaks it. Switch
    // to comparing resolved `cgColor` components under a pinned trait if that
    // happens.
    #expect(standardTitle == UIColor(Color.ink))
    #expect(standardLarge == UIColor(Color.ink))
    #expect(scrollEdgeLarge == UIColor(Color.ink))
  }
}
