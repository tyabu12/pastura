// K/N sealed-class subtype dot-syntax access regression guard —
// Issue #220 W4 PR-A Item 1.
//
// Locks the empirical finding that K/N's swift_name dot-syntax DOES export
// sealed-class subtypes accessibly from Swift. PR-C documented a
// "swift_name dot-syntax barrier" inline (never runtime-tested); W4 PR-A
// Item 1 re-diagnosed it as **Swift module shadowing** in the Pastura/
// target (`Pastura.SimulationEvent` Swift enum vs PasturaShared's K/N
// class), not a K/N export defect — the fix is `PasturaShared.` module
// qualification at the call site, not a Kotlin facade.
//
// This suite runs in PasturaTests/, which does NOT import the Pastura
// module and therefore has no shadowing — so unqualified names resolve
// directly to PasturaShared's K/N exports. That makes it a clean
// regression-guard surface for the K/N export shape itself. The companion
// production-side proof (using the `PasturaShared.` qualifier under
// shadowing) lives in `Pastura/Pastura/KMPSpike/PasturaSharedSpike.swift`
// — both surfaces must keep working for the dot-syntax pattern to remain
// load-bearing for production K/N integration.
//
// Verified shapes:
//
//  - SimulationEvent.SimulationCompleted.shared   (sealed-class `object` singleton)
//  - SimulationError.Cancelled.shared             (same shape, separate sealed class)
//  - SimulationEvent.PhaseStarted(...)            (sealed-class data-class subtype constructor)
//  - event as? SimulationEvent.PhaseStarted       (subtype-cast pattern match)
//
// The one path that genuinely fails is the FLAT MANGLED NAME form
// (`SimulationEventPhaseStarted(...)`, `SimulationErrorCancelled.shared`) —
// `swift_name` correctly hides it. That is intentional K/N behaviour, not a
// regression, so this suite asserts only the dot-syntax-works direction.

import PasturaShared
import Testing

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct KNDotSyntaxAccessTests {

  // MARK: - sealed-class `object` singleton access via .shared

  @Test func simulationEventSimulationCompletedShared() {
    let first: SimulationEvent = SimulationEvent.SimulationCompleted.shared
    let second: SimulationEvent = SimulationEvent.SimulationCompleted.shared
    #expect(first === second, "Singleton `.shared` must return the same instance across accesses")
  }

  @Test func simulationErrorObjectSingletonsAccessible() {
    let cancelled: SimulationError = SimulationError.Cancelled.shared
    let modelNotLoaded: SimulationError = SimulationError.ModelNotLoaded.shared
    let retriesExhausted: SimulationError = SimulationError.RetriesExhausted.shared

    // Distinct singleton classes — pointer-distinct.
    #expect(cancelled !== modelNotLoaded)
    #expect(modelNotLoaded !== retriesExhausted)
    #expect(cancelled !== retriesExhausted)

    // Same .shared call twice → same pointer.
    #expect(SimulationError.Cancelled.shared === SimulationError.Cancelled.shared)
  }

  // MARK: - sealed-class data class subtype construction via dot-syntax

  @Test func simulationEventPhaseStartedConstructor() {
    let event: SimulationEvent = SimulationEvent.PhaseStarted(
      phaseType: PhaseType.speakAll, phasePath: [0]
    )
    // Pattern match — sealed-class subtype is exposed as a Swift Obj-C class,
    // so the production-side pattern-match path is `as?` cast (not Swift
    // `switch case .x` which is enum-only).
    guard let started = event as? SimulationEvent.PhaseStarted else {
      Issue.record("`as?` cast rejected a SimulationEvent.PhaseStarted constructed via dot-syntax")
      return
    }
    #expect(started.phaseType == PhaseType.speakAll)
    #expect(started.phasePath == [0])
  }

  @Test func simulationErrorScenarioValidationFailedConstructor() {
    let err: SimulationError = SimulationError.ScenarioValidationFailed(message: "test-msg")
    guard let failed = err as? SimulationError.ScenarioValidationFailed else {
      Issue.record(
        "`as?` cast rejected a SimulationError.ScenarioValidationFailed constructed via dot-syntax"
      )
      return
    }
    #expect(failed.message == "test-msg")
  }
}
