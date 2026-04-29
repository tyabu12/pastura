import SwiftUI
import Testing

@testable import Pastura

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GameHeaderStatusTests {

  // MARK: - Case enumeration

  @Test func sevenCasesEnumerated() {
    // Pin the 7-case shape — adding/removing a case is an API-level change
    // that must update this test alongside `SimulationViewModel.status`'s
    // derivation precedence and `Localizable.xcstrings` entries.
    #expect(GameHeaderStatus.allCases.count == 7)
    let expected: Set<GameHeaderStatus> = [
      .simulating, .demoing, .replaying, .paused, .completed, .cancelled, .error
    ]
    #expect(Set(GameHeaderStatus.allCases) == expected)
  }

  // MARK: - Labels (en source — ja covered by `localization-coverage` CI)

  @Test func simulatingLabelMatchesEnSource() {
    #expect(GameHeaderStatus.simulating.label == "Simulating")
  }

  @Test func demoingLabelMatchesEnSource() {
    #expect(GameHeaderStatus.demoing.label == "Demoing")
  }

  @Test func replayingLabelMatchesEnSource() {
    #expect(GameHeaderStatus.replaying.label == "Replaying")
  }

  @Test func pausedLabelMatchesEnSource() {
    // "Paused" (state form) preferred over "Pause" (verb) per existing
    // SimulationView convention + iOS HIG state-label guidance.
    #expect(GameHeaderStatus.paused.label == "Paused")
  }

  @Test func completedLabelMatchesEnSource() {
    #expect(GameHeaderStatus.completed.label == "Completed")
  }

  @Test func cancelledLabelMatchesEnSource() {
    #expect(GameHeaderStatus.cancelled.label == "Cancelled")
  }

  @Test func errorLabelMatchesEnSource() {
    #expect(GameHeaderStatus.error.label == "Error")
  }

  @Test func allLabelsAreNonEmpty() {
    for status in GameHeaderStatus.allCases {
      #expect(!status.label.isEmpty, "Empty label for \(status)")
    }
  }

  // MARK: - Color groupings (relative — see commit 3 GameHeaderContractTests
  //          for absolute moss / mossDark / muted token verification)

  @Test func activeModesShareForeground() {
    // simulating / demoing / replaying all use the same active-mode tone.
    #expect(GameHeaderStatus.simulating.foreground == GameHeaderStatus.demoing.foreground)
    #expect(GameHeaderStatus.simulating.foreground == GameHeaderStatus.replaying.foreground)
  }

  @Test func terminalExceptionsShareForeground() {
    // paused / cancelled / error share the terminal-exception tone.
    // Semantic distinction (cancelled vs paused vs error) is preserved at
    // the enum level even when colors collapse — derivation precedence in
    // `SimulationViewModel.status` is what consumers branch on.
    #expect(GameHeaderStatus.paused.foreground == GameHeaderStatus.cancelled.foreground)
    #expect(GameHeaderStatus.paused.foreground == GameHeaderStatus.error.foreground)
  }

  @Test func completedHasDistinctForegroundFromActiveAndTerminal() {
    // Completed earns its own tone (mossDark) — a "successfully done" accent
    // distinct from both active modes (moss) and terminal exceptions (muted).
    #expect(GameHeaderStatus.completed.foreground != GameHeaderStatus.simulating.foreground)
    #expect(GameHeaderStatus.completed.foreground != GameHeaderStatus.paused.foreground)
  }

  @Test func activeAndTerminalForegroundsAreDistinct() {
    #expect(GameHeaderStatus.simulating.foreground != GameHeaderStatus.paused.foreground)
  }

  // MARK: - Background = foreground.opacity(0.14) per design hand-off

  @Test func backgroundIsForegroundAt14PercentOpacity() {
    // Pin the relationship per design hand-off (HEADER_UPDATE.md / §2.12
    // headerRule + status pill spec). Computed (not stored) so a future
    // override cannot drift the background tone away from its foreground.
    for status in GameHeaderStatus.allCases {
      #expect(status.background == status.foreground.opacity(0.14))
    }
  }

  // MARK: - Raw value stability (xcstrings keys / debugging)

  @Test func rawValuesAreLowercaseCaseNames() {
    // Defensive: `String` rawValue is the lowercased case name. If a future
    // change uses Codable for persistence (e.g. routing through xcstrings
    // catalog keys by raw value), this stability matters.
    #expect(GameHeaderStatus.simulating.rawValue == "simulating")
    #expect(GameHeaderStatus.cancelled.rawValue == "cancelled")
    #expect(GameHeaderStatus.error.rawValue == "error")
  }
}
