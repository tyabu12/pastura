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

  // MARK: - Token routing (label and wash pinned together)

  /// One row per case. Exhaustive over `allCases` by construction, and the
  /// two pins at the head of ``everyCaseRoutesToItsDeclaredLabelAndWashTokens``
  /// are what keep it that way — a bare loop over a hand-maintained fixture
  /// passes vacuously the moment a row is dropped.
  ///
  /// A struct rather than a tuple because swiftlint's `large_tuple` caps
  /// tuples at two members and a row needs three. Same reason as
  /// ``MossWashSite``.
  private static let routing: [StatusRouting] = [
    StatusRouting(.simulating, label: Color.mossOnWash, wash: Color.moss),
    StatusRouting(.demoing, label: Color.mossOnWash, wash: Color.moss),
    StatusRouting(.replaying, label: Color.mossOnWash, wash: Color.moss),
    StatusRouting(.completed, label: Color.mossInk, wash: Color.mossDark),
    StatusRouting(.paused, label: Color.muted, wash: Color.muted),
    StatusRouting(.cancelled, label: Color.muted, wash: Color.muted),
    StatusRouting(.error, label: Color.muted, wash: Color.muted)
  ]

  /// Change-detector for the pill's colour routing, in the shape of
  /// ``PhaseTypeLabelTokenTests`` / ``ScenarioBadgeStyleTokenTests``.
  /// A failure here is not a bug — it means a code-review-gated token
  /// drifted. Confirm the change was intended, then update the row.
  ///
  /// **This replaces four relative-grouping tests, two of which could never
  /// fire.** The old `completedHasDistinctForegroundFromActiveAndTerminal`
  /// and `activeAndTerminalForegroundsAreDistinct` asserted that two tokens
  /// *differ*; per `.claude/rules/view-testing.md`, a `PasturaDynamicColor`-
  /// backed alias compares by provider instance, so such an assertion passes
  /// whatever the tokens are. Their doc comments also went on naming `moss` /
  /// `mossDark` after #1455 moved the labels off them — the grouping tests
  /// were structurally blind to *which* token each arm read, which is exactly
  /// the gap #1455 was filed about.
  ///
  /// An earlier comment here deferred absolute token verification to
  /// `GameHeaderContractTests`. That file asserts no tokens at all and never
  /// did, so until now nothing pinned them anywhere.
  ///
  /// Token *values* stay `DesignTokensTests`' contract and the contrast
  /// claims are `DesignTokensTests+MossOnWash`'s / `+MossInkAsWashLabel`'s. This
  /// suite guards only the routing. Note there is deliberately no "label
  /// differs from wash" assertion — it would be one of the vacuous `!=`
  /// shapes above; the muted arms legitimately route both to the same token,
  /// and the table is what records which arms split.
  @Test func everyCaseRoutesToItsDeclaredLabelAndWashTokens() {
    #expect(Self.routing.count == GameHeaderStatus.allCases.count)
    #expect(Set(Self.routing.map(\.status)) == Set(GameHeaderStatus.allCases))

    for row in Self.routing {
      #expect(row.status.foreground == row.label, "label token for \(row.status)")
      #expect(row.status.washToken == row.wash, "wash token for \(row.status)")
    }
  }

  // MARK: - Background = washToken.opacity(washAlpha)

  @Test func backgroundIsTheWashTokenAtTheDeclaredAlpha() {
    // The alpha itself is unchanged from the design hand-off (HEADER_UPDATE.md
    // / §2.12 status pill spec); what moved is which token it is applied to.
    //
    // This replaces `backgroundIsForegroundAt14PercentOpacity`, which pinned
    // `background == foreground.opacity(0.14)` so that "a future override
    // cannot drift the background tone away from its foreground". That
    // invariant was written before the `*-on-wash` role tokens existed, when
    // label and wash genuinely were one token — and holding it is what made
    // all four moss arms self-washes below AA in light. Every translucent-wash
    // site that owes AA already separates the two (the `mossWashSites` /
    // `inkWashSites` fixtures enumerate them), so the split is the established
    // shape rather than a drift this test should catch. The carve-out is §8's
    // quietude tier, where the two legitimately stay one token — this enum's
    // own `muted` arms are in it, as is `ResultsView.pending`.
    // What survives of the original intent is the pin below: the tone is
    // still derived from one declared token at one declared alpha, not
    // hand-set per case.
    for status in GameHeaderStatus.allCases {
      #expect(status.background == status.washToken.opacity(GameHeaderStatus.washAlpha))
    }
    #expect(GameHeaderStatus.washAlpha == 0.14)
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

// MARK: - Helpers

/// One `GameHeaderStatus` case's declared colour routing: which token paints
/// the label, and which one fills the capsule beneath it.
struct StatusRouting {
  let status: GameHeaderStatus
  let label: Color
  let wash: Color

  init(_ status: GameHeaderStatus, label: Color, wash: Color) {
    self.status = status
    self.label = label
    self.wash = wash
  }
}
