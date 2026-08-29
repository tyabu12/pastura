import Foundation
import Testing

@testable import Pastura

/// Pins the ADR-023 S3b RNG seam to known-answer vectors shared with
/// `shared/engine/src/commonTest/.../RandomSourceTests.kt`. A change to either
/// side that breaks a vector here is a parity break, whatever the Swift-only
/// tests say.
struct RandomSourceTests {
  /// Reference SplitMix64 output for seed 0 (matches Vigna's reference
  /// implementation) and for an arbitrary non-zero seed.
  @Test(arguments: [
    (
      UInt64(0),
      [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC]
    ),
    (
      UInt64(0x1234_5678_9ABC_DEF0),
      [0x1619_22C6_45CE_50E8, 0xAD76_0CAF_A169_7B60, 0x3501_FF44_902C_A50D, 0x417C_B9A8_26D8_31DF]
    )
  ])
  func splitMix64MatchesReferenceVectors(seed: UInt64, expected: [UInt64]) {
    let source = SplitMix64RandomSource(seed: seed)
    #expect((0..<4).map { _ in source.nextUInt64() } == expected)
  }

  /// `index(below:)` is `% n` and nothing cleverer — the Kotlin twin pins the
  /// same four indices for the same seed.
  @Test func indexReducesByModulo() {
    let source = SplitMix64RandomSource(seed: 0)
    #expect((0..<4).map { _ in source.index(below: 7) } == [2, 1, 2, 4])
  }

  /// `unit()` takes the top 53 bits, so the doubles are exact and shared.
  @Test func unitTakesTopFiftyThreeBits() {
    let source = SplitMix64RandomSource(seed: 0)
    let expected = [
      0.8833108082136426, 0.43152799704850997, 0.026433771592597743, 0.9708819781538285
    ]
    #expect((0..<4).map { _ in source.unit() } == expected)
  }

  /// The same seed restarts the same stream; a different seed does not.
  @Test func seedDeterminesTheStream() {
    let first = SplitMix64RandomSource(seed: 42)
    let same = SplitMix64RandomSource(seed: 42)
    let other = SplitMix64RandomSource(seed: 43)
    let stream = (0..<8).map { _ in first.nextUInt64() }
    #expect(stream == (0..<8).map { _ in same.nextUInt64() })
    #expect(stream != (0..<8).map { _ in other.nextUInt64() })
  }

  /// The production source draws from the system generator: helper values
  /// stay in range and the raw stream is not constant.
  @Test func systemSourceHelpersStayInRange() {
    let source = SystemRandomSource()
    for _ in 0..<64 {
      #expect((0..<5).contains(source.index(below: 5)))
      let unit = source.unit()
      #expect(unit >= 0.0 && unit < 1.0)
    }
    #expect(Set((0..<16).map { _ in source.nextUInt64() }).count > 1)
  }
}
