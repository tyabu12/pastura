import Testing

@testable import Pastura

/// Tests for `SimulationEvent.languageMismatch` Equatable conformance
/// (ADR-010 Step E PR2 item 3). The auto-synthesized Equatable on
/// `SimulationEvent` carries the contract; these pins guard against
/// (i) future associated-value reorders (`(agent, detected, expected)`
/// → `(agent, expected, detected)` would silently flip equality), and
/// (ii) `Optional<String>` synthesis breakage in a future Swift
/// version. Sendable is implicitly tested by the existing
/// `nonisolated public enum` declaration; this file focuses on
/// equality semantics.
@Suite(.timeLimit(.minutes(1)))
struct SimulationEventLanguageMismatchTests {
  @Test func equalCases() {
    let lhs = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    let rhs = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    #expect(lhs == rhs)
  }

  @Test func nilDetectedEqualsNilDetected() {
    let lhs = SimulationEvent.languageMismatch(agent: "Alice", detected: nil, expected: "en")
    let rhs = SimulationEvent.languageMismatch(agent: "Alice", detected: nil, expected: "en")
    #expect(lhs == rhs)
  }

  @Test func nilDetectedNotEqualToStringDetected() {
    let nilCase = SimulationEvent.languageMismatch(agent: "Alice", detected: nil, expected: "en")
    let strCase = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    #expect(nilCase != strCase)
  }

  @Test func differentDetectedNotEqual() {
    let detectedJa = SimulationEvent.languageMismatch(
      agent: "Alice", detected: "ja", expected: "en")
    let detectedKo = SimulationEvent.languageMismatch(
      agent: "Alice", detected: "ko", expected: "en")
    #expect(detectedJa != detectedKo)
  }

  @Test func differentExpectedNotEqual() {
    let toEn = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    let toJa = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "ja")
    #expect(toEn != toJa)
  }

  @Test func differentAgentNotEqual() {
    // Per critic pass 2 — pin identity-on-agent so event-drain filtering
    // by agent stays sound if a future refactor re-orders associated values.
    let alice = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    let bob = SimulationEvent.languageMismatch(agent: "Bob", detected: "ja", expected: "en")
    #expect(alice != bob)
  }

  @Test func notEqualToDifferentCase() {
    let mismatch = SimulationEvent.languageMismatch(agent: "Alice", detected: "ja", expected: "en")
    let started = SimulationEvent.inferenceStarted(agent: "Alice")
    #expect(mismatch != started)
  }
}
