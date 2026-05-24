// H8 hypothesis async surface (Issue #220 W3 PR-C).
//
// Verifies that an `@Observable` Swift class bridging Kotlin/Native (K/N)
// value-typed state to SwiftUI invalidation works ACROSS an actor
// boundary — the snapshot-cache pattern documented in PR #216
// (`SimulationViewModel.isPaused` ↔ `SimulationRunner.isPaused`)
// translated to a Sendable backing actor.
//
// H8-5 surface: async actor read-back. The 4 mutation surfaces already
// proven in W3 PR-B (`H8BridgeTests.swift`) — H8-1 scalar, H8-2
// collection, H8-3 enum, H8-4 `access`/`withMutation` bridge — covered
// only synchronous mutation. H8-5 closes the orthogonal axis: state
// owned by an `actor` that the `@Observable` VM reads asynchronously,
// where the VM's sync getter contract requires a local snapshot cache.
//
// CRITICAL escalation rule: if any test fails, file
// `r8-observable-bridge-failure` comment on Issue #220 and pause spike —
// Tier 1 hard blocker. Do NOT silently rescope.

import Observation
import PasturaShared
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct H8AsyncBridgeTests {

  // H8-5 runtime test added in the next commit.
}

/// Non-`@Observable` actor backing K/N value-typed state for H8-5.
/// The `@Observable` VM bridges to this actor via a snapshot cache —
/// see `H8AsyncBridgeViewModel` for the pattern.
///
// MARK: - Why `actor`, not `final class`?
//
// Intentionally an `actor`, not a `final class @unchecked Sendable`. The
// `final class` shape would trip `swift-isolation.md` Pattern 4 if any
// future maintainer adds a sync accessor: under
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, a `Sendable`-conforming
// class with sync methods silently binds to MainActor, breaking the
// `nonisolated` callers that need to await it. Actors carry their own
// explicit isolation; sync vs async methods don't shift the isolation
// the way they do on classes.
private actor KNStateActor {
  private var state: Pairing

  init(initial: Pairing) {
    self.state = initial
  }

  func read() -> Pairing {
    state
  }

  func update(_ newValue: Pairing) {
    state = newValue
  }
}

/// `@Observable` test fixture exposing K/N value-typed state owned by
/// an `actor`. Snapshot-cache pattern: VM owns a local `cache` (sync
/// getter returns it), `refresh()` reads from the actor and triggers
/// SwiftUI invalidation via `withMutation`.
///
/// Three load-bearing pinnings (each identified by pre-impl critic):
///
/// 1. **`@ObservationIgnored private var cache: Pairing`** — the
///    `@Observable` macro instruments ALL stored `var` properties at
///    the type level, regardless of access level. Without
///    `@ObservationIgnored`, the macro would generate a redundant
///    auto-observation channel on `cache` itself, making H8-5 silently
///    collapse to a duplicate of H8-1 (which already proved scalar
///    macro instrumentation works) — testing nothing about actor
///    read-back. The annotation makes `cache` purely backing storage;
///    the only observation channel is the computed `var pairing`
///    going through `access` / `withMutation`.
///
/// 2. **Computed getter, NO setter exposed** — callers must go
///    through `refresh()` to update state. A macro-stored
///    `var pairing: Pairing` would auto-instrument the setter and
///    let consumers write directly, bypassing the actor (silent cache
///    desync). The snapshot-cache contract is "actor is canonical,
///    cache is derived" — only `refresh()` propagates actor changes
///    to cache.
///
/// 3. **Direct `await` in `refresh()`, NO inner `Task { }`** —
///    spawning a detached `Task` lets `refresh()` return before the
///    `withMutation` block runs, breaking `@Test` determinism. The
///    direct-await form keeps the actor hop and the MainActor
///    mutation in the same continuation; `withMutation` fires
///    synchronously on the resumed MainActor before `refresh()`
///    returns.
@Observable
@MainActor
private final class H8AsyncBridgeViewModel {

  /// Local snapshot of the actor's state. `@ObservationIgnored` opts
  /// it out of macro instrumentation — observation goes through the
  /// computed `var pairing` only. See type-level doc-comment §1.
  @ObservationIgnored private var cache: Pairing

  /// Backing actor — the canonical store. Production callers MUST NOT
  /// reach into the actor directly; the snapshot-cache contract is
  /// that `cache` mirrors the actor's state after `refresh()`, and
  /// any other write path desyncs them. Test-only mutation goes
  /// through `_testOnlyUpdateActor(_:)`.
  ///
  /// `@ObservationIgnored` is technically redundant on `let` (the
  /// macro instruments `var` only) but signals intent and
  /// future-proofs against a refactor swapping `let` → `var`.
  @ObservationIgnored private let stateActor: KNStateActor

  /// Computed property exposing the cached snapshot to SwiftUI
  /// observation. `access(keyPath: \.pairing)` registers the
  /// observation channel on read; the matching `withMutation` in
  /// `refresh()` fires invalidation on write.
  var pairing: Pairing {
    access(keyPath: \.pairing)
    return cache
  }

  /// Cache + actor MUST be seeded identically at init to preserve
  /// snapshot-cache consistency. Subsequent `refresh()` keeps them
  /// in sync; until the first `refresh()`, `cache` and the actor's
  /// state are equal by construction.
  init(initial: Pairing) {
    self.cache = initial
    self.stateActor = KNStateActor(initial: initial)
  }

  /// Read the actor's canonical state and propagate to the local
  /// snapshot via `withMutation`. Direct `await` (NOT inner
  /// `Task { }`) is load-bearing for test determinism — see
  /// type-level doc-comment §3.
  func refresh() async {
    let snapshot = await stateActor.read()
    withMutation(keyPath: \.pairing) {
      self.cache = snapshot
    }
  }

  /// Test-only helper: forwards to `stateActor.update(_:)` without
  /// triggering `refresh()`. Production code MUST NOT use this
  /// path — the snapshot-cache contract requires `refresh()` after
  /// every actor mutation. The leading underscore + `_testOnly`
  /// prefix signals "do not call from production".
  func _testOnlyUpdateActor(_ newValue: Pairing) async {
    await stateActor.update(newValue)
  }
}

/// Class-box workaround for `withObservationTracking`'s `onChange`
/// closure (`@Sendable @escaping`). Mirrors the same-named helper in
/// `H8BridgeTests.swift` — Swift's file-scoped `private` doesn't cross
/// files, so this declaration must live here too. Extracting to a
/// shared `KMPSpike/TestSupport.swift` is deferred to spike cleanup
/// (W6 GO/NO-GO path).
///
/// `@unchecked Sendable` is sound: only the test author writes into
/// this box, and Observation's dispatch fires `onChange` synchronously
/// on the mutating call under `@MainActor` isolation.
private final class ObservationFireSignal: @unchecked Sendable {
  var fired = false
}
