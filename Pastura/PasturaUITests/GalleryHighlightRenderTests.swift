import XCTest

/// Render probe for `GalleryHighlightRunFigure` (ADR-029, #1394).
///
/// This is the narrow exception `view-testing.md` rule 2 allows: the target is
/// not reachable from pure logic. `swiftui-traps.md` § "iOS 26 AttributeGraph
/// crash — ForEach + glyph in a plain-ScrollView card" documents that a render
/// crash in exactly this container shape — `GalleryScenarioDetailView` is a
/// plain `ScrollView` over an eager `VStack`, under a `.large` title, with a
/// `.background(…ignoresSafeArea())` — stays **green** under `xcodebuild build`
/// and the whole unit suite. The run figure adds an unconditional `SheepAvatar`
/// and a `PhaseTypeLabel` capsule to a `ForEach` inside it, which is the shape
/// named there. Only navigating in and rendering can tell us.
///
/// It needs its own launch argument because the default `--ui-test` canary
/// serves no highlight: `StubGalleryService.fetchHighlightData` 404s unless the
/// fixture seeds one, so a probe run under `--ui-test` would find the section
/// collapsed to `EmptyView()` and pass without ever building the view. Seeding
/// the highlight into the default fixture instead would push
/// `galleryDetail.tryButton` below the fold for the navigation flows that tap
/// it without scrolling.
@MainActor
final class GalleryHighlightRenderTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  override func tearDownWithError() throws {
    XCUIApplication().terminate()
  }

  func testGalleryDetailRendersTheHighlightRunFigure() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test", "--ui-test-seed-highlight"]
    app.launch()

    XCTAssertTrue(
      app.navigationBars["Pastura"].waitForExistence(timeout: 10),
      "Home did not appear within 10s.")

    let browseTab = app.tabBars.buttons["Browse"]
    XCTAssertTrue(browseTab.waitForExistence(timeout: 5), "Browse tab missing.")
    browseTab.tap()

    let galleryCell = app.buttons["sharedScenarios.galleryCell.ui_test_canary"]
    XCTAssertTrue(
      galleryCell.waitForExistence(timeout: 5),
      "Canary gallery cell missing — StubGalleryService fixture may be wrong.")
    galleryCell.tap()

    // Type-agnostic on purpose. `.accessibilityIdentifier` on a container that
    // is not itself an accessibility element does **not** publish one queryable
    // `otherElement` — it propagates the identifier down to each leaf, so the
    // matches here are the figure's `StaticText`s. Measured: an
    // `app.otherElements[…]` query finds nothing while the subtree is fully
    // rendered, which would read as a render failure.
    let runFigure = app.descendants(matching: .any)
      .matching(identifier: "galleryDetail.highlightRunFigure")
      .firstMatch
    // The highlight is fetched by a `.task(id:)` running alongside the screen's
    // own load, so it lands slightly after the detail view itself.
    XCTAssertTrue(
      runFigure.waitForExistence(timeout: 10),
      """
      Highlight run figure never rendered. Either the view failed to build \
      (check ~/Library/Logs/DiagnosticReports/Pastura-*.ips for an \
      AttributeGraph fault stack rather than trusting this message), or a \
      loader gate hid the section — the fixture is schema-valid, attested, and \
      uses only mappable phases, so a gate firing is itself the bug.
      """)

    // Pinned to the **combined** label, which is the row's real contract: each
    // utterance is one accessibility element carrying speaker, phase and line
    // (`.accessibilityElement(children: .combine)` in `stream(_:)`). Asserting
    // the bare line instead would not distinguish a combined row from three
    // loose `Text`s — measured, that query passes either way — so it proved the
    // panel rendered but said nothing about the reading.
    XCTAssertTrue(
      app.staticTexts["Alice, Speak, はじめまして、よろしく。"].waitForExistence(timeout: 5),
      "Run figure rendered but its first excerpt row did not, or stopped combining.")

    // The divider is the one branch that fires only on a round change, so the
    // fixture spans two rounds specifically to reach it. Without this the
    // three-row excerpt would prove the loop but not the boundary.
    XCTAssertTrue(
      app.staticTexts["Round 2 / 2"].waitForExistence(timeout: 5),
      "Round divider missing between the round-1 and round-2 excerpt lines.")

    // The fixture spans both speak phases so the per-row `PhaseTypeLabel`
    // differs; the second row's combined label is where that shows up. The
    // badge's glyph stays `.accessibilityHidden(true)` — it is the unconditional
    // Capsule this whole probe exists for, reachable only through the row's
    // combined reading.
    XCTAssertTrue(
      app.staticTexts["Alice, Speak Each, では、そろそろ本題に入ろう。"]
        .waitForExistence(timeout: 5),
      "The round-2 row, whose phase badge differs from round 1's, did not render.")
  }
}
