import Foundation
import Synchronization

/// Source of raw 64-bit randomness for every draw the Engine makes.
///
/// The seam exists for ADR-023 Stage 4 (issue #501, S3b): the Kotlin engine
/// carries an identical interface, so a cross-language parity fixture can hand
/// both engines the same seeded stream and expect the same `assign random_one`
/// / `event_inject` outcomes. Handlers never call the stdlib ranged draws
/// (`Int.random(in:)`, `randomElement()`, `Double.random(in:)`) — those reduce
/// the raw bits with platform-specific algorithms that disagree with Kotlin's
/// even on the same seed. They call ``index(below:)`` / ``unit()`` instead,
/// whose reductions are spelled out here and mirrored bit-for-bit in
/// `shared/engine/.../RandomSource.kt`.
///
/// `Sendable` because it is stored in the `Sendable` ``PhaseContext``; a
/// stateful conformer guards its own state (see ``SplitMix64RandomSource``).
/// Draw *order* is part of the parity contract: handlers run sequentially
/// within a run, so two engines given the same seed consume the same stream
/// in the same order.
nonisolated public protocol RandomSource: Sendable {
  /// The next 64 raw bits of the stream, uniformly distributed.
  func nextUInt64() -> UInt64
}

extension RandomSource {
  /// A uniform index in `0..<n`, reduced as `nextUInt64() % n`.
  ///
  /// Modulo bias is accepted on purpose: the reduction must be identical on
  /// both engines, and its statistical quality is irrelevant to the choices
  /// it drives (which topic, which wolf, which event).
  ///
  /// - Precondition: `count > 0`. Every caller draws from a pool it has already
  ///   proven non-empty (`AssignHandler` guards `topics` / `active`,
  ///   `EventInjectHandler` resets `remaining` before drawing), so a zero here
  ///   is a handler bug, not a runtime condition to absorb. Swift traps on
  ///   `% 0`; Kotlin throws — the contract is the same either way.
  public func index(below count: Int) -> Int {
    precondition(count > 0, "RandomSource.index(below:) requires a non-empty pool")
    return Int(nextUInt64() % UInt64(count))
  }

  /// A uniform `Double` in `[0, 1)`, built from the top 53 bits so the value
  /// is exact and identical to Kotlin's `(bits ushr 11) * 2^-53`.
  public func unit() -> Double {
    Double(nextUInt64() >> 11) * 0x1.0p-53
  }
}

/// The production ``RandomSource``: the platform's cryptographically-seeded
/// generator, so injecting the seam changes nothing about shipped behaviour.
nonisolated public struct SystemRandomSource: RandomSource {
  public init() {}

  public func nextUInt64() -> UInt64 {
    var generator = SystemRandomNumberGenerator()
    return generator.next()
  }
}

/// SplitMix64 (Steele, Lea & Flood 2014; Vigna's reference constants), the
/// seeded ``RandomSource`` parity fixtures use.
///
/// Chosen for being a dozen lines with no lookup table, so the Kotlin twin is
/// trivially the same code — `RandomSourceTests` pins both to shared
/// known-answer vectors. The `Mutex` makes the conformer honestly `Sendable`;
/// it is never contended, because draws are sequential within a run (the
/// parity precondition stated on ``RandomSource``).
nonisolated public final class SplitMix64RandomSource: RandomSource {
  private let state: Mutex<UInt64>

  /// - Parameter seed: The stream's seed; the same seed yields the same
  ///   sequence on both engines.
  public init(seed: UInt64) {
    state = Mutex(seed)
  }

  public func nextUInt64() -> UInt64 {
    state.withLock { seed in
      seed &+= 0x9E37_79B9_7F4A_7C15
      var mixed = seed
      mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
      mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
      return mixed ^ (mixed >> 31)
    }
  }
}
