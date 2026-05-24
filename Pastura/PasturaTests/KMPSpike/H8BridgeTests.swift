// H8 hypothesis full bridge test suite (Issue #220 W3 PR-B).
//
// Verifies that an `@Observable` Swift class wrapping Kotlin/Native (K/N)
// value types triggers SwiftUI invalidation across four mutation surfaces:
//
// - H8-1: scalar field reassignment (`var pairing: Pairing`)
// - H8-2: in-place collection mutation (`var phases: [Phase]`)
// - H8-3: enum case change (`var phaseType: PhaseType`)
// - H8-4: `access(keyPath:)` / `withMutation(keyPath:)` bridge to a
//   non-`@Observable` K/N-state holder (PR #216 pattern faithful
//   translation across the K/N boundary)
//
// W3 PR-A landed the compile-time smoke (`PasturaSharedSpike.H8Smoke`);
// this suite converts it to runtime evidence via Swift Testing and
// absorbs the smoke entirely.
//
// CRITICAL escalation rule: if any test fails, file
// `r8-observable-bridge-failure` comment on Issue #220 and pause spike —
// Tier 1 hard blocker. Do NOT silently rescope.

import Observation
import PasturaShared
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct H8BridgeTests {

  /// H8-1: Reassigning a K/N scalar value-typed property on an
  /// `@Observable` class triggers `withObservationTracking.onChange`.
  /// Verifies that K/N's `data class` export (Kotlin: immutable `val`
  /// properties, Swift: class-typed reference) integrates cleanly with
  /// Swift's `@Observable` macro instrumentation on whole-instance
  /// replacement.
  @Test
  func scalarMutationTriggersObservation() {
    let signal = ObservationFireSignal()
    let viewModel = H8BridgeTestViewModel()

    withObservationTracking {
      _ = viewModel.pairing.agent1
    } onChange: {
      signal.fired = true
    }

    viewModel.pairing = Pairing(
      agent1: "Charlie",
      agent2: "Dave",
      action1: "cooperate",
      action2: nil
    )

    #expect(signal.fired == true)
  }

  /// H8-2: In-place mutation of a Swift `Array`-typed property whose element
  /// type is a K/N export triggers observation. Verifies that Swift's
  /// `@Observable` macro `_modify` accessor instrumentation fires on
  /// `.append` against `var phases: [Phase]`, not just on whole-array
  /// reassignment. Important because production K/N consumers (Engine port,
  /// W6+) will mutate phase collections incrementally.
  @Test
  func collectionMutationTriggersObservation() {
    let signal = ObservationFireSignal()
    let viewModel = H8BridgeTestViewModel()

    withObservationTracking {
      _ = viewModel.phases.count
    } onChange: {
      signal.fired = true
    }

    viewModel.phases.append(makeNoOpPhase(.speakAll))

    #expect(signal.fired == true)
  }

  /// H8-3: Reassigning a K/N enum-typed property triggers observation.
  /// `PhaseType` (10 cases) exercises K/N's `UPPER_SNAKE_CASE` → Swift
  /// `lowerCamelCase` export convention (Kotlin's `@SerialName` is the
  /// JSON wire label, NOT the Swift identifier). Verifies that case
  /// transition between two distinct values fires `@Observable` macro
  /// invalidation just like scalar replacement.
  ///
  /// Originally planned with `PairingStrategy` but that K/N enum has
  /// only one case (`.roundRobin`); switched to `PhaseType` for actual
  /// case-transition coverage.
  @Test
  func enumMutationTriggersObservation() {
    let signal = ObservationFireSignal()
    let viewModel = H8BridgeTestViewModel()

    withObservationTracking {
      _ = viewModel.phaseType
    } onChange: {
      signal.fired = true
    }

    viewModel.phaseType = .vote

    #expect(signal.fired == true)
  }
}

/// `@Observable` test fixture wrapping K/N value types. Lives in the test
/// target so production source carries no test-only scaffolding (W3 PR-A's
/// `PasturaSharedSpikeViewModel` is absorbed here in item 5).
///
/// Properties grow as H8-1..H8-4 are added in successive commits.
@Observable
@MainActor
final class H8BridgeTestViewModel {

  /// H8-1: scalar K/N value type. Macro-instrumented setter fires
  /// observation on whole-instance replacement.
  var pairing: Pairing

  /// H8-2: Swift `Array` of K/N exports. Macro `_modify` accessor fires
  /// observation on in-place mutation (`.append`, `.remove(at:)`).
  var phases: [Phase]

  /// H8-3: K/N enum (10 cases via Kotlin's `UPPER_SNAKE_CASE` →
  /// Swift `lowerCamelCase` export). Macro-instrumented setter fires
  /// observation on case transition.
  var phaseType: PhaseType

  init(
    pairing: Pairing = Pairing(
      agent1: "Alice",
      agent2: "Bob",
      action1: nil,
      action2: nil
    ),
    phases: [Phase] = [],
    phaseType: PhaseType = .speakAll
  ) {
    self.pairing = pairing
    self.phases = phases
    self.phaseType = phaseType
  }
}

/// No-op `Phase` factory exercising the K/N data class's 16-arg init
/// (all optionals default to nil). Kept test-local to avoid coupling to
/// `PasturaSharedSpike.makeNoOpPhase` (which is `internal` to the Pastura
/// target and would require `@testable import Pastura`).
private func makeNoOpPhase(_ type: PhaseType) -> Phase {
  Phase(
    type: type,
    prompt: nil,
    outputSchema: nil,
    options: nil,
    pairing: nil,
    logic: nil,
    template: nil,
    source: nil,
    target: nil,
    excludeSelf: nil,
    subRounds: nil,
    condition: nil,
    thenPhases: nil,
    elsePhases: nil,
    probability: nil,
    eventVariable: nil
  )
}

/// Class-box workaround for `withObservationTracking`'s `onChange`
/// closure. The closure is `@Sendable @escaping`, so capturing
/// `var fired = false` directly fails Swift 6 strict concurrency
/// ("mutation of captured var ... in concurrently-executing code").
/// Routing through a reference-type box lets the closure mutate
/// *through* a captured `let` instead.
///
/// `@unchecked Sendable` is sound here: only the test author writes
/// into this box, and Observation's dispatch fires `onChange`
/// synchronously on the mutating call under `@MainActor` isolation
/// (W3 PR-A `H8Smoke.verifyBridgeFires` documents this contract).
final class ObservationFireSignal: @unchecked Sendable {
  var fired = false
}
