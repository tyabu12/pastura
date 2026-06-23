import Foundation
import Testing

@testable import Pastura

/// Pacing-floor (proportional turn dwell) tests for ``ReplayViewModel``.
///
/// Sibling extension of `ReplayViewModelTests` (NOT a new `@Suite`) per
/// `.claude/rules/testing.md` — a separate suite would run in parallel and
/// race the VM-spawning original on the shared test process.
extension ReplayViewModelTests {

  // MARK: - typingCharsPerSecond accessor (single source of truth)

  @Test func typingCharsPerSecondForwardsConfigNil() throws {
    // `fastConfig` leaves `typingCharsPerSecond` at its `nil` default.
    let viewModel = try Self.makeVM()
    #expect(viewModel.typingCharsPerSecond == nil)
  }

  @Test func typingCharsPerSecondForwardsConfigValue() throws {
    let source = try Self.makeSource()
    let viewModel = ReplayViewModel(
      sources: [source], config: .demoDefault, contentFilter: ContentFilter())
    #expect(viewModel.typingCharsPerSecond == PlaybackSpeed.normal.charsPerSecond)
  }

  // MARK: - showAllThoughts ownership (moved from host @State)

  @Test func showAllThoughtsDefaultsToTrue() throws {
    let viewModel = try Self.makeVM()
    #expect(viewModel.showAllThoughts)
  }
}
