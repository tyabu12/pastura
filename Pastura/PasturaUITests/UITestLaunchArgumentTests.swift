import XCTest

/// Smoke test for the `--ui-test` launch argument. Confirms the UI-test DI
/// branch in `PasturaApp.initialize()` completes setup and transitions past
/// the "Initializing..." progress view, without requiring the real LLM or
/// network-backed `GalleryService`.
final class UITestLaunchArgumentTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testAppLaunchesPastInitializingWithUITestArgument() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()

    // Home renders its navigation title "Pastura" once setup completes.
    // If the UI-test branch fails, the "Initializing..." ProgressView stays
    // up and this assertion times out.
    let navTitle = app.navigationBars["Pastura"]
    XCTAssertTrue(
      navTitle.waitForExistence(timeout: 10),
      "App did not reach Home within 10s — UI-test DI branch likely failed.")
  }
}
