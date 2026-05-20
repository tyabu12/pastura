// Issue #220 W3 PR-A scope (a) — first iOS-side consumer of the KMP
// `PasturaShared.xcframework`. Lives outside the strict dependency-rule
// layers (Models/LLM/Engine/Data/Views/App) because the spike intentionally
// keeps KMP scaffolding off the production graph until W6 GO decision.
//
// Do NOT import this from production code. Reference from new spike-only
// callsites only. NO-GO path deletes `Pastura/Pastura/KMPSpike/` whole.

import Observation
import PasturaShared

/// Spike-scope sandbox demonstrating iOS-side consumption of the KMP
/// `PasturaShared` Models layer (Issue #220 W3 PR-A).
///
/// Exercises three K/N → Swift interop surfaces per 1st pre-impl
/// critic Axis 8 (the single-`Pairing` proposal would have biased Q9
/// shim-LOC measurement low):
///
/// 1. **Data class init + property read** — `Pairing` (4 fields, two
///    optionals exercising K/N null-vs-omit semantics).
/// 2. **Enum case access** — `PairingStrategy.roundRobin` (Kotlin
///    `@SerialName("round_robin")` enum, K/N exports as class-property
///    `roundRobin` on the enum class).
/// 3. **Nested-collection optionality** — `Phase` with
///    `Map<String, String>?`, `List<String>?`, `List<Phase>?` fields.
///
/// Companion type `PasturaSharedSpikeViewModel` exercises the H8
/// hypothesis smoke (see below).
@MainActor
enum PasturaSharedSpike {
  /// Construct a `Pairing` from Swift, verifying the K/N init bridge
  /// preserves Kotlin's argument order (`agent1`, `agent2`, then the
  /// two `String?` action fields with null-default semantics).
  static func samplePairing() -> Pairing {
    Pairing(
      agent1: "Alice",
      agent2: "Bob",
      action1: nil,
      action2: nil
    )
  }

  /// Reference the `@SerialName("round_robin")` enum case via Swift's
  /// camelCase mapping. K/N exposes enum entries as class-readonly
  /// properties on the enum class itself (visible via the framework
  /// header as `@property (class, readonly) PairingStrategy *roundRobin`).
  static let pairingStrategy: PairingStrategy = .roundRobin

  /// Construct a no-op `Phase` to exercise the nested-collection
  /// optionality (Q9 shim-LOC measurement). Phase's init exposes
  /// every field as an explicit parameter — including all optionals
  /// — so the spike's call site doubles as a smoke for that
  /// surface area.
  static func makeNoOpPhase(of type: PhaseType) -> Phase {
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
}

/// Minimal smoke for the H8 hypothesis (Issue #220 Tier 1 hard
/// blocker): an `@Observable` Swift class wrapping a K/N value type
/// must trigger SwiftUI invalidation on mutation.
///
/// PR-B (next session) lands the full H8 test suite covering the
/// `access(keyPath:)` / `withMutation(keyPath:)` bridge pattern
/// (PR #216) and edge cases (collection mutation, nested-type
/// invalidation, async actor read-back). This file's
/// `H8Smoke.verifyBridgeFires` is a compile-time smoke that runs
/// the simplest case: assignment-replaces-instance.
///
/// **CRITICAL — escalation rule on failure**: If this smoke fails
/// (compile error, runtime assertion fires, or
/// `verifyBridgeFires() == false`), the failure is load-bearing R8
/// evidence affecting the entire spike GO decision. File an
/// `r8-observable-bridge-failure` comment on #220 with reproduction
/// details and pause W3 PR-A pending spike re-evaluation. **Do NOT
/// silently rescope to PR-B** — the descope ladder in ROADMAP /
/// Issue #220 explicitly forbids it for Tier 1 hard blockers.
@Observable
@MainActor
final class PasturaSharedSpikeViewModel {
  /// `Pairing`-backed state. Mutation here must trigger SwiftUI
  /// invalidation for downstream `@Observable` consumers.
  var pairing: Pairing

  init(pairing: Pairing = PasturaSharedSpike.samplePairing()) {
    self.pairing = pairing
  }
}

/// Compile-time + runtime smoke for the H8 hypothesis. Callable from
/// `#Preview` or PR-B's full H8 test for early signal.
@MainActor
enum H8Smoke {
  /// Returns `true` iff mutating `PasturaSharedSpikeViewModel.pairing`
  /// fires `withObservationTracking`'s `onChange` closure. Returns
  /// `false` if the observation tracker did not fire — indicating
  /// the @Observable bridge does NOT propagate through K/N value
  /// types and the spike's H8 hypothesis fails.
  ///
  /// Synchronous — `withObservationTracking`'s `onChange` fires on
  /// the next runloop turn after mutation, but the observation
  /// registration itself is synchronous. We register, mutate, and
  /// then read the flag immediately because `@Observable`'s
  /// invalidation path runs synchronously on assignment under
  /// MainActor isolation.
  static func verifyBridgeFires() -> Bool {
    let viewModel = PasturaSharedSpikeViewModel()
    // Class box: `withObservationTracking`'s `onChange` closure is
    // `@escaping`, so under Swift 6 strict concurrency it cannot
    // mutate a captured `var` (compile error: "mutation of captured
    // var ... in concurrently-executing code"). Box the flag in a
    // reference type so the closure mutates *through* the captured
    // `let` rather than mutating the captured variable itself.
    let signal = ObservationFireSignal()
    withObservationTracking {
      _ = viewModel.pairing.agent1
    } onChange: {
      signal.fired = true
    }
    // Replace the pairing instance (no in-place mutation since
    // K/N data classes expose immutable val properties).
    viewModel.pairing = Pairing(
      agent1: "Alice",
      agent2: "Bob",
      action1: "cooperate",
      action2: nil
    )
    return signal.fired
  }
}

/// Reference-type flag for `H8Smoke.verifyBridgeFires`. Must be
/// `nonisolated` because (a) the enclosing file uses
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so the class would
/// otherwise inherit MainActor isolation, and (b)
/// `withObservationTracking`'s `onChange` is `@Sendable @escaping`,
/// invoking from a non-MainActor context that cannot mutate a
/// MainActor-isolated property. `@unchecked Sendable` is sound in
/// this narrow usage because `verifyBridgeFires` itself is
/// MainActor-isolated and the `onChange` callback is invoked
/// synchronously on the same actor in practice — but the type
/// system needs the explicit opt-out for the closure signature.
nonisolated private final class ObservationFireSignal: @unchecked Sendable {
  var fired = false
}
