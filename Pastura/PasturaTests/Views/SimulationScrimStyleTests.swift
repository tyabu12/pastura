import SwiftUI
import Testing

@testable import Pastura

/// Change-detector for the loading scrim's fill token (#1284).
///
/// A failure here is not a bug — it means a code-review-gated token drifted.
/// Confirm the change passed review, then update the expectation.
///
/// Why this exists: `SimulationView.loadingScrim` covers the app ground, so its
/// fill must be darker than every ground it can sit on. A paired `Color.*`
/// alias cannot satisfy that — `Color.ink` resolves `nightInk` in dark and
/// composites *lighter* than the night ground, which is the regression device
/// QA caught. Nothing else guards it: the SwiftLint rule reaches
/// `shadow(color:)` only, and ADR-009 rules out the snapshot test that would
/// otherwise see it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SimulationScrimStyleTests {

  /// Pins WHICH token the scrim reads. `DesignTokensTests` owns what the token
  /// is worth; this asserts the consumer still reads that one and has not been
  /// re-pointed at an appearance-following alias.
  @Test func scrimFillReadsTheFixedOccluderToken() {
    #expect(SimulationScrimStyle.fill == PasturaPalette.scrim.color)
  }

  /// The occluder must be darker than every ground it covers, which is the
  /// property `PasturaPalette.scrim` exists to hold. Asserted against the two
  /// grounds it actually sits on rather than as a bare value check, so the test
  /// states the requirement rather than restating the hex.
  @Test func scrimIsDarkerThanBothGrounds() {
    let scrim = PasturaPalette.scrim
    for ground in [PasturaPalette.screenBackground, PasturaPalette.nightBackground] {
      #expect(scrim.red < ground.red)
      #expect(scrim.green < ground.green)
      #expect(scrim.blue < ground.blue)
    }
  }
}
