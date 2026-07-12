import XCTest

extension XCTestCase {
  /// Performs the interactive left-edge back-swipe and asserts the pop landed
  /// on `sentinel`.
  ///
  /// The coordinate drag is required on iOS 17+ — `swipeRight()` does not
  /// trigger `interactivePopGestureRecognizer`. On the GPU-less CI simulator
  /// the gesture is occasionally dropped outright, which no amount of waiting
  /// recovers (the pop simply never started). So this re-issues the drag once
  /// if `sentinel` has not appeared within `timeout`, then asserts. Bounded at
  /// two attempts: a genuinely-broken pop still fails within ~2×`timeout`
  /// rather than hanging, keeping the red signal fast (#1053).
  ///
  /// Assumes `timeout` comfortably exceeds a legitimate-but-slow pop, so the
  /// retry fires only on a truly-dropped gesture. If a pop actually started but
  /// was merely slow (> `timeout`), the second drag over-pops one screen
  /// further — safe only where the caller's assertion still holds one level up.
  @MainActor
  func edgeSwipeBack(
    in app: XCUIApplication,
    until sentinel: XCUIElement,
    timeout: TimeInterval = 5,
    message: @autoclosure () -> String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    start.press(forDuration: 0.15, thenDragTo: end)
    var appeared = sentinel.waitForExistence(timeout: timeout)
    if !appeared {
      // Gesture likely dropped on the GPU-less runner — re-issue once.
      start.press(forDuration: 0.15, thenDragTo: end)
      appeared = sentinel.waitForExistence(timeout: timeout)
    }
    XCTAssertTrue(appeared, message(), file: file, line: line)
  }
}
