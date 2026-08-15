import Testing

@testable import Pastura

/// Unit tests for the simulator-runnable, inference-free parts of the #1105
/// DRY anti-repetition sampler: `DryConfig.resolve(environment:)` (the shipped
/// default + harness A/B override logic), `withArrayOfCStrings` (the
/// C-string pointer-lifetime helper that feeds `llama_sampler_init_dry`), and
/// the #1483 diagnostic line shapes.
///
/// The seeding + apply paths (`buildAndSeedDrySampler`, `fillApplyAndSelect`)
/// require real inference and are unrunnable on the simulator (PR #463) — they
/// are validated on device / via the pastura-harness A/B (#1105), not here.
/// What #1483 made testable is only the *line format* those paths emit: the
/// emission itself still needs a harness run to observe.
@Suite(.timeLimit(.minutes(1)))
struct DrySamplerConfigTests {

  // MARK: - DryConfig.resolve(environment:)

  @Test func resolveDefaultsToShippedConstants() {
    let config = DryConfig.resolve(environment: [:])
    #expect(config?.multiplier == 0.8)  // DryConfig.defaultMultiplier
    #expect(config?.base == 1.75)
    #expect(config?.allowedLength == 3)
    #expect(config?.penaltyLastN == 512)
    #expect(config?.seqBreakers == ["\n"])
  }

  @Test func resolveHonorsMultiplierOverride() {
    let config = DryConfig.resolve(environment: ["PASTURA_DRY_MULTIPLIER": "0.5"])
    #expect(config?.multiplier == 0.5)
    // Other fields keep the shipped defaults.
    #expect(config?.base == 1.75)
  }

  @Test func resolveDisablesOnZeroMultiplier() {
    // The harness base arm — `PASTURA_DRY_MULTIPLIER=0` turns DRY off.
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_MULTIPLIER": "0"]) == nil)
  }

  @Test func resolveDisablesOnNegativeMultiplier() {
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_MULTIPLIER": "-1"]) == nil)
  }

  @Test func resolveHonorsAllFieldOverrides() {
    let config = DryConfig.resolve(environment: [
      "PASTURA_DRY_MULTIPLIER": "1.1",
      "PASTURA_DRY_BASE": "1.5",
      "PASTURA_DRY_ALLOWED_LENGTH": "5",
      "PASTURA_DRY_LAST_N": "256"
    ])
    #expect(config?.multiplier == 1.1)
    #expect(config?.base == 1.5)
    #expect(config?.allowedLength == 5)
    #expect(config?.penaltyLastN == 256)
  }

  @Test func resolveIgnoresUnparseableOverride() {
    // A non-numeric override falls back to the default rather than disabling.
    let config = DryConfig.resolve(environment: ["PASTURA_DRY_MULTIPLIER": "abc"])
    #expect(config?.multiplier == 0.8)
  }

  // MARK: - withArrayOfCStrings pointer lifetime

  // The recursive nested-`withCString` builder must keep every C-string pointer
  // alive for the whole `body` call (the real `body` runs
  // `llama_sampler_init_dry`, which reads the pointers before deep-copying).
  // A regression here would be a silent use-after-free, so pin that the bytes
  // are readable back inside `body`.
  @Test func withArrayOfCStringsKeepsPointersReadableInBody() {
    let service = makeTestService()
    let inputs = ["\n", "。", "multi word breaker"]

    let readBack: [String] = service.withArrayOfCStrings(inputs) { buffer in
      #expect(buffer.count == inputs.count)
      return buffer.map { ptr in
        ptr.flatMap { String(cString: $0) } ?? "<null>"
      }
    }

    #expect(readBack == inputs)
  }

  @Test func withArrayOfCStringsHandlesEmptyInput() {
    let service = makeTestService()
    let count = service.withArrayOfCStrings([]) { $0.count }
    #expect(count == 0)
  }

  // MARK: - Harness-observable diagnostic lines (#1483)

  /// The `reason=` vocabulary is the join key for the `.stderr.log` sweep in
  /// `/model-eval` Step 2, whose expectations are written per reason. Pinning
  /// the exact set means a rename — or a sixth exit path — fails here instead
  /// of silently emitting a marker the sweep has no expectation for.
  @Test func dryUnavailableReasonsArePinnedAndDistinct() {
    let raws = DryUnavailableReason.allCases.map(\.rawValue)
    // A copy-pasted raw value would make two exit paths indistinguishable in
    // the sweep — the exact confusion the per-path markers exist to prevent.
    #expect(Set(raws).count == raws.count)
    #expect(Set(raws) == ["disabled", "no-seeds", "no-model", "null-init", "no-grammar"])
  }

  /// `nCtxTrain` is the load-bearing field: llama.cpp b10327 **drops** that
  /// argument from `llama_sampler_init_dry`, so recording the value the pinned
  /// b8694 build passes is what makes this a baseline rather than a liveness
  /// check (#1415). Dropping it from the line must fail a test.
  @Test func drySeededLineCarriesEveryField() throws {
    let config = try #require(DryConfig.resolve(environment: [:]))
    let line = LlamaCppService.drySeededLine(
      seededTokenCount: 42, seedCount: 3, nCtxTrain: 8192,
      config: config, model: "test-model")

    #expect(line.hasPrefix("samplerDrySeeded "))
    #expect(line.contains("seededTokens=42"))
    #expect(line.contains("seeds=3"))
    #expect(line.contains("nCtxTrain=8192"))
    #expect(line.contains("mult=0.8"))
    #expect(line.contains("base=1.75"))
    #expect(line.contains("allowed=3"))
    #expect(line.contains("lastN=512"))
    #expect(line.contains("model=test-model"))
    // The sweep is line-oriented; an embedded newline would let one event
    // inflate a `grep -c` into two.
    #expect(!line.contains("\n"))
  }

  @Test func dryUnavailableLineCarriesReasonAndModel() {
    for reason in DryUnavailableReason.allCases {
      let line = LlamaCppService.dryUnavailableLine(reason: reason, model: "test-model")
      #expect(line.hasPrefix("samplerDryUnavailable reason=\(reason.rawValue)"))
      #expect(line.contains("model=test-model"))
      #expect(!line.contains("\n"))
      // Neither marker may contain the other, or a per-marker `grep -c`
      // silently counts both and the two exit classes stop being separable.
      #expect(!line.contains("samplerDrySeeded"))
    }
  }
}
