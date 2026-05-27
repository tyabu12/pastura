// H4 hypothesis — encode/canonicalize performance measurement —
// Issue #220 W4 PR-A Item 3.
//
// ## Methodology
//
// **These three @Test methods are 3 DISTINCT METRICS, not 3 paths of the
// same transform. DO NOT cross-compare their `mean` / `median` values.**
//
// Each path measures a different input shape AND a different transform
// scope; comparing one to another would be category error. Read each
// individually to answer its own question, then triangulate against
// H6 ≤10MB / W6 GO/NO-GO criteria:
//
// 1. **`canonicalize-stage-only`** — pre-encode a K/N Scenario to JSON
//    tree OUTSIDE the measure loop, measure `Canonicalizer.canonicalize`
//    on the tree. Answers: "what's the cost of the cross-language
//    wire-shape normalizer alone?"
//
// 2. **`kn-encode-only`** — measure `ScenarioCodec.encodeToString` end-
//    to-end on a K/N Scenario. Answers: "what's the cost of crossing the
//    K/N FFI to encode a Scenario into its JSON wire shape?"
//
// 3. **`swift-yams-roundtrip`** — measure `Yams.YAMLEncoder().encode` +
//    `Yams.YAMLDecoder().decode` on a Swift native `Pastura.Scenario`.
//    Answers: "what's the cost of Pastura's existing Swift-side Codable
//    + Yams baseline for the same conceptual workload?" — useful as a
//    sanity-check anchor for the K/N numbers above.
//
// ## Fixture rationale
//
// 5 personas + 10 phases (`largeScenarioFixtureKMP` /
// `largeScenarioFixtureSwift`). Distinct from Q9's 1 persona + 1 phase
// in `PasturaSharedSpike.sampleScenario()`. **Do NOT retroactively
// recompute Q9 LOC ratios against this fixture** — different size class,
// different concern (Q9 = shim-LOC surface measurement, H4 = perf cost on
// production-shape scenario).
//
// ## Measurement discipline
//
// - warm-up 10 iterations before sample collection (drains JIT noise)
// - sample 50 iterations (n=50 trades signal stability vs CI cost)
// - `ContinuousClock` (Swift 5.7+) — monotonic, attosecond resolution
// - aggregate-then-print: ONE `print` per @Test (NOT per-sample dump)
// - output format: `[H4-DIRECT] path=<name> mean=Xms median=Yms stddev=Zms n=50`
//   parse-able by future ADR-004 amendment writers via grep on `[H4-DIRECT]`
//
// **`print` is intentional, not `Issue.record` or `#expect`** — per W3
// PR-C 2nd critic Critical Axis 6: these tests must NOT fail when slow.
// They're measurement-only — H6 ≤10MB and ADR-004 amendment consume the
// raw numbers, not pass/fail status. Tests assert only that the
// measurement ran (samples.count == 50).

import Foundation
import Pastura
import PasturaShared
import Testing
import Yams

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct H4PerformanceTests {

  // MARK: - Fixtures (5 personas + 10 phases, K/N + Swift parallel)

  private static let largeScenarioFixtureKMP: PasturaShared.Scenario = {
    let personas: [PasturaShared.Persona] = (1...5).map { idx in
      PasturaShared.Persona(name: "Agent\(idx)", description: "Persona \(idx) for H4 fixture")
    }
    let phases: [PasturaShared.Phase] = (1...10).map { _ in
      PasturaShared.Phase(
        type: PasturaShared.PhaseType.speakAll,
        prompt: "Phase prompt for H4 fixture",
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
    return PasturaShared.Scenario(
      id: "h4-fixture-kmp",
      name: "H4 measurement fixture",
      description: "5 personas / 10 phases — H4 perf measurement",
      language: "en",
      simulationLanguage: nil,
      agentCount: 5,
      rounds: 1,
      context: "H4 fixture context",
      personas: personas,
      phases: phases,
      extraData: [:]
    )
  }()

  private static let largeScenarioFixtureSwift: Pastura.Scenario = {
    let personas: [Pastura.Persona] = (1...5).map { idx in
      Pastura.Persona(name: "Agent\(idx)", description: "Persona \(idx) for H4 fixture")
    }
    let phases: [Pastura.Phase] = (1...10).map { _ in
      Pastura.Phase(
        type: .speakAll,
        prompt: "Phase prompt for H4 fixture",
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
    return Pastura.Scenario(
      id: "h4-fixture-swift",
      name: "H4 measurement fixture",
      description: "5 personas / 10 phases — H4 perf measurement",
      language: "en",
      simulationLanguage: nil,
      agentCount: 5,
      rounds: 1,
      context: "H4 fixture context",
      personas: personas,
      phases: phases,
      extraData: [:]
    )
  }()

  // MARK: - Measurement helpers

  private static let warmupCount = 10
  private static let sampleCount = 50

  /// `ContinuousClock.Duration` → milliseconds. Duration's
  /// `components.attoseconds` resolves to attosecond precision; 1 ms
  /// = 1e15 attoseconds.
  private static func milliseconds(_ duration: Duration) -> Double {
    let seconds = Double(duration.components.seconds)
    let attoseconds = Double(duration.components.attoseconds)
    return seconds * 1_000 + attoseconds / 1e15
  }

  /// Population stats — mean, median, sample standard deviation.
  private struct Stats {
    let mean: Double
    let median: Double
    let stddev: Double
  }

  private static func computeStats(_ samples: [Double]) -> Stats {
    let count = Double(samples.count)
    let mean = samples.reduce(0, +) / count
    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    let variance = samples.reduce(0) { $0 + pow($1 - mean, 2) } / count
    return Stats(mean: mean, median: median, stddev: sqrt(variance))
  }

  private static func reportStats(path: String, samples: [Double]) {
    let stats = computeStats(samples)
    let line = String(
      format: "[H4-DIRECT] path=%@ mean=%.3fms median=%.3fms stddev=%.3fms n=%lld",
      path, stats.mean, stats.median, stats.stddev, Int64(samples.count)
    )
    print(line)
  }

  // MARK: - Path 1 — Canonicalize stage only

  @Test func h4Path1CanonicalizeStageOnly() {
    let scenario = Self.largeScenarioFixtureKMP
    // Pre-encode OUTSIDE the measure loop — this path isolates the
    // canonicalize-stage cost from any encode work.
    let tree = ScenarioCodec.shared.encodeToJsonElement(scenario: scenario)
    let canonicalizer = Canonicalizer.shared

    let clock = ContinuousClock()
    for _ in 0..<Self.warmupCount {
      _ = canonicalizer.canonicalize(tree: tree, polymorphicDiscriminatorValues: Set<String>())
    }

    var samples: [Double] = []
    samples.reserveCapacity(Self.sampleCount)
    for _ in 0..<Self.sampleCount {
      let elapsed = clock.measure {
        _ = canonicalizer.canonicalize(tree: tree, polymorphicDiscriminatorValues: Set<String>())
      }
      samples.append(Self.milliseconds(elapsed))
    }

    Self.reportStats(path: "canonicalize-stage-only", samples: samples)
    // `count == sampleCount` catches a future refactor that conditionally
    // skips appends; `contains { $0 > 0 }` catches an all-zero outcome
    // that would signal the measure closure was elided (functionally
    // unreachable today but guards against compiler optimization
    // surprises in tighter Release builds).
    #expect(samples.count == Self.sampleCount && samples.contains { $0 > 0 })
  }

  // MARK: - Path 2 — K/N encode end-to-end

  @Test func h4Path2KNEncodeOnly() {
    let scenario = Self.largeScenarioFixtureKMP
    let codec = ScenarioCodec.shared

    let clock = ContinuousClock()
    for _ in 0..<Self.warmupCount {
      _ = codec.encodeToString(scenario: scenario)
    }

    var samples: [Double] = []
    samples.reserveCapacity(Self.sampleCount)
    for _ in 0..<Self.sampleCount {
      let elapsed = clock.measure {
        _ = codec.encodeToString(scenario: scenario)
      }
      samples.append(Self.milliseconds(elapsed))
    }

    Self.reportStats(path: "kn-encode-only", samples: samples)
    #expect(samples.count == Self.sampleCount && samples.contains { $0 > 0 })
  }

  // MARK: - Path 3 — Swift native Yams roundtrip

  @Test func h4Path3SwiftYamsRoundtrip() throws {
    let scenario = Self.largeScenarioFixtureSwift
    let encoder = YAMLEncoder()
    let decoder = YAMLDecoder()

    let clock = ContinuousClock()
    for _ in 0..<Self.warmupCount {
      let yaml = try encoder.encode(scenario)
      _ = try decoder.decode(Pastura.Scenario.self, from: yaml)
    }

    var samples: [Double] = []
    samples.reserveCapacity(Self.sampleCount)
    for _ in 0..<Self.sampleCount {
      let elapsed = try clock.measure {
        let yaml = try encoder.encode(scenario)
        _ = try decoder.decode(Pastura.Scenario.self, from: yaml)
      }
      samples.append(Self.milliseconds(elapsed))
    }

    Self.reportStats(path: "swift-yams-roundtrip", samples: samples)
    #expect(samples.count == Self.sampleCount && samples.contains { $0 > 0 })
  }
}
