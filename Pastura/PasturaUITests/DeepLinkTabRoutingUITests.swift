import XCTest

/// Verifies ADR-016 **D5.2** end-to-end: a deep link resolving to a gallery
/// scenario selects the さがす (Search) tab and pushes
/// `.galleryScenarioDetail` onto **that** tab's router — the target tab is
/// fixed by the resolution kind, NOT the currently-selected (launch-default
/// Home) tab.
///
/// The coordinator-level mechanism is unit-tested in `TabCoordinatorTests`;
/// this covers the `tryDrain` / `applyResolution` glue that no unit test can
/// reach. The deep link is injected via the DEBUG-only
/// `--ui-test-open-deeplink` launch hook, which queues the URL before
/// `.ready` so the existing gate drains it once dependencies are up — the
/// same queue-then-drain path a real pre-`.ready` `onOpenURL` takes.
@MainActor
final class DeepLinkTabRoutingUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    // Explicit terminate so the simulator releases the app process before the
    // next test class launches a fresh one (mirrors NavigationRegressionTests;
    // avoids background-assertion infra errors on resource-tight CI sims).
    XCUIApplication().terminate()
  }

  func testDeepLinkSelectsSearchTabAndPushesGalleryDetail() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "--ui-test",
      "--ui-test-open-deeplink", "pastura://scenario/ui_test_canary"
    ]
    app.launch()

    // The drain pushes GalleryScenarioDetailView onto the Search tab's stack.
    // Because all four tab NavigationStacks are mounted at once, only the
    // *selected* tab's pushed content renders — so the Try button being
    // on-screen proves the detail landed on the foreground (Search) stack.
    let tryButton = app.buttons["galleryDetail.tryButton"]
    XCTAssertTrue(
      tryButton.waitForExistence(timeout: 10),
      "Deep link did not drain to the gallery detail — Search tab + push glue regressed.")

    // D5.2 positive: the さがす tab (accessibilityLabel "Browse") is selected.
    XCTAssertTrue(
      app.tabBars.buttons["Browse"].isSelected,
      "Search tab is not selected after the deep link.")

    // D5.2 negative (load-bearing): the app launched on Home, so a passing
    // test must prove it switched AWAY from the launch-default tab — the
    // target tab is fixed by the resolution kind, not the current selection.
    XCTAssertFalse(
      app.tabBars.buttons["Home"].isSelected,
      "Home tab is still selected — deep link did not switch to the Search tab.")
  }
}
