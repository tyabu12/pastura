//
//  PasturaUITestsLaunchTests.swift
//  PasturaUITests
//
//  Created by Tomohito Yabu on 2026/04/06.
//

import XCTest

final class PasturaUITestsLaunchTests: XCTestCase {

  override static var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunch() throws {
    let app = XCUIApplication()
    app.launch()

    // Insert steps here to perform after app launch but before taking a screenshot,
    // such as logging into a test account or navigating somewhere in the app
    // XCUIAutomation Documentation
    // https://developer.apple.com/documentation/xcuiautomation

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
