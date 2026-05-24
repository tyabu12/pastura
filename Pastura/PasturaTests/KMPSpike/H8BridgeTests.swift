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

  init(
    pairing: Pairing = Pairing(
      agent1: "Alice",
      agent2: "Bob",
      action1: nil,
      action2: nil
    )
  ) {
    self.pairing = pairing
  }
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
