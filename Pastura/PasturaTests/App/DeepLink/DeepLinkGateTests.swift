import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DeepLinkGateTests {
  // MARK: - Initial state

  @Test func freshGateHasZeroCount() {
    let gate = DeepLinkGate()
    #expect(gate.sheetPresentationCount == 0)
  }

  @Test func freshGateHasNoPendingURL() {
    let gate = DeepLinkGate()
    #expect(gate.pendingURL == nil)
  }

  @Test func freshGateIsNotSheetActive() {
    let gate = DeepLinkGate()
    #expect(gate.isSheetActive == false)
  }

  // MARK: - Increment

  @Test func incrementMakesSheetActive() {
    let gate = DeepLinkGate()
    gate.sheetPresentationCount += 1
    #expect(gate.isSheetActive == true)
  }

  // MARK: - Nested increment / decrement

  @Test func nestedIncrementRemainsActiveAfterOneDecrement() {
    let gate = DeepLinkGate()
    gate.sheetPresentationCount += 1
    gate.sheetPresentationCount += 1
    gate.sheetPresentationCount -= 1
    #expect(gate.isSheetActive == true)
  }

  @Test func nestedIncrementBecomesInactiveAfterBothDecrements() {
    let gate = DeepLinkGate()
    gate.sheetPresentationCount += 1
    gate.sheetPresentationCount += 1
    gate.sheetPresentationCount -= 1
    gate.sheetPresentationCount -= 1
    #expect(gate.isSheetActive == false)
  }

  // MARK: - pendingURL most-recent-wins

  @Test func pendingURLReplacedByLatest() throws {
    let gate = DeepLinkGate()
    let first = try #require(URL(string: "pastura://scenario/abc"))
    let second = try #require(URL(string: "pastura://scenario/xyz"))

    gate.pendingURL = first
    gate.pendingURL = second

    #expect(gate.pendingURL == second)
  }

  // MARK: - Bool transition across present / dismiss cycle
  //
  // The cellular consent dialog (#191) opts into the gate via a hidden
  // `Color.clear.deepLinkGated()` marker that mounts on
  // `pendingCellularConsent != nil` and unmounts on nil. The two tests
  // below exercise the counter shape that wiring depends on: the
  // `isSheetActive` flag must trip true on +1 and false on the
  // matching -1, and a fresh present after a clean dismiss must
  // raise the flag again rather than getting wedged. SwiftUI
  // `.deepLinkGated()` itself goes through `onAppear`/`onDisappear`,
  // so the gate's correctness here is what guarantees the dialog can
  // toggle deep-link drainage on every show, not just the first.

  @Test func isSheetActiveTransitionsAcrossSingleCycle() {
    let gate = DeepLinkGate()
    #expect(gate.isSheetActive == false)
    gate.sheetPresentationCount += 1
    #expect(gate.isSheetActive == true)
    gate.sheetPresentationCount -= 1
    #expect(gate.isSheetActive == false)
  }

  @Test func isSheetActiveTripsAgainOnRePresentation() {
    let gate = DeepLinkGate()
    gate.sheetPresentationCount += 1
    gate.sheetPresentationCount -= 1
    #expect(gate.isSheetActive == false)
    gate.sheetPresentationCount += 1
    #expect(gate.isSheetActive == true)
  }
}
