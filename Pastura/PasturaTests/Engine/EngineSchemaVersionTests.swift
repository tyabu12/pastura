import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct EngineSchemaVersionTests {

  // MARK: - Baseline constant

  @Test func baselineIsOne() {
    #expect(EngineSchemaVersion.current == 1)
  }

  // MARK: - D2 (phase-capability) branch

  @Test func nilPhasesAreUnconstrained() {
    // A legacy/older feed with no `phases` field must not grey out — the
    // index gate cannot determine capability, so it defers to D3 + the
    // parse-throw backstop.
    #expect(EngineSchemaVersion.isCompatible(phases: nil, minEngineVersion: nil))
  }

  @Test func emptyPhasesAreCompatible() {
    #expect(EngineSchemaVersion.isCompatible(phases: [], minEngineVersion: nil))
  }

  @Test func allKnownPhasesAreCompatible() {
    let known = PhaseType.allCases.map(\.rawValue)
    #expect(EngineSchemaVersion.isCompatible(phases: known, minEngineVersion: nil))
  }

  @Test func everyCurrentPhaseKindIsIndividuallyCompatible() {
    // No shipped phase kind may grey out at baseline.
    for phase in PhaseType.allCases {
      #expect(
        EngineSchemaVersion.isCompatible(phases: [phase.rawValue], minEngineVersion: nil),
        "\(phase.rawValue) should be compatible at baseline")
    }
  }

  @Test func unknownPhaseIsIncompatible() {
    #expect(
      !EngineSchemaVersion.isCompatible(
        phases: ["vote", "future_phase"], minEngineVersion: nil))
  }

  // MARK: - D3 (declared min_engine_version) branch

  @Test func minEngineVersionEqualToCurrentIsCompatible() {
    #expect(
      EngineSchemaVersion.isCompatible(
        phases: nil, minEngineVersion: EngineSchemaVersion.current))
  }

  @Test func minEngineVersionZeroIsCompatible() {
    #expect(EngineSchemaVersion.isCompatible(phases: nil, minEngineVersion: 0))
  }

  @Test func minEngineVersionAboveCurrentIsIncompatible() {
    #expect(
      !EngineSchemaVersion.isCompatible(
        phases: nil, minEngineVersion: EngineSchemaVersion.current + 1))
  }

  @Test func knownPhasesButFutureMinEngineVersionIsIncompatible() {
    // D3 alone gates a scenario whose phases are all known but which
    // declares a future requirement (a semantics-only or non-phase break).
    #expect(
      !EngineSchemaVersion.isCompatible(
        phases: ["vote", "speak_all"],
        minEngineVersion: EngineSchemaVersion.current + 1))
  }

  // MARK: - OR-composition

  @Test func bothGatesFailingIsIncompatible() {
    #expect(
      !EngineSchemaVersion.isCompatible(
        phases: ["future_phase"],
        minEngineVersion: EngineSchemaVersion.current + 1))
  }
}
