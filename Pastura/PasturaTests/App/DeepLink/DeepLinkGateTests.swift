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
}
