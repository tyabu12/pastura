import Testing

@testable import Pastura

/// Pure-formatter tests for the inference-stats label string used in
/// `SimulationView`'s frosted header. The formatter returns `nil`
/// when both inputs are nil (lets the caller short-circuit and
/// render nothing); otherwise it emits the existing
/// `"<tps> tok/s • <duration>s"` layout with `—` placeholders for
/// individually-nil inputs.
@Suite(.timeLimit(.minutes(1)))
struct InferenceStatsFormatterTests {

  @Test func returnsNilWhenBothInputsNil() {
    #expect(
      InferenceStatsFormatter.format(durationSeconds: nil, tokensPerSecond: nil) == nil)
  }

  // Inputs use exactly-representable IEEE-754 values (halves) so
  // the `%.1f` rounding output is deterministic across platforms —
  // 1.85 rounds platform-dependently to 1.8 or 1.9.
  @Test func formatsBothPopulated() {
    #expect(
      InferenceStatsFormatter.format(durationSeconds: 1.5, tokensPerSecond: 12.5)
        == "12.5 tok/s • 1.5s")
  }

  @Test func emitsDashWhenDurationNil() {
    #expect(
      InferenceStatsFormatter.format(durationSeconds: nil, tokensPerSecond: 12.5)
        == "12.5 tok/s • —")
  }

  @Test func emitsDashWhenTokensPerSecondNil() {
    #expect(
      InferenceStatsFormatter.format(durationSeconds: 1.5, tokensPerSecond: nil)
        == "— tok/s • 1.5s")
  }
}
