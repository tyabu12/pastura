import XCTest

/// Regression guard for manual QA scenario 2: "Back gesture from any depth."
/// Verifies that navigating from Home → Share Board and then tapping the
/// navigation back button returns to the Home screen, not an intermediate
/// state or root re-render.
///
/// Uses the nav-bar back button rather than a swipe-right edge gesture because
/// `XCUITest` swipe gestures have variable hit-area reliability depending on
/// device/simulator frame size; the back button is deterministic.
@MainActor
final class BackGestureTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testSwipeBackFromShareBoardReturnsToHome() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"]
    app.launch()

    // Wait for Home to finish initializing.
    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    // Home → Share Board.
    let shareBoardButton = app.buttons["home.shareBoardButton"]
    XCTAssertTrue(
      shareBoardButton.waitForExistence(timeout: 5),
      "Share Board button missing on Home.")
    shareBoardButton.tap()

    XCTAssertTrue(
      app.navigationBars["Share Board"].waitForExistence(timeout: 5),
      "Share Board did not appear after tap.")

    // Tap the leading back button on the Share Board nav bar to pop back.
    app.navigationBars.firstMatch.buttons.firstMatch.tap()

    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 5),
      "Home nav bar did not reappear after back — navigation pop failed.")
  }
}
