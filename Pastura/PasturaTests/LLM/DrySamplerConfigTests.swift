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
/// Only the *line format* is testable; the emission still needs a harness run.
///
/// Specifically **not** pinned here: which `guard` emits which reason. Swapping
/// `.disabled` and `.noSeeds` between two guards would pass everything below and
/// silently mislabel every harness sweep. Closing that needs an injectable emit
/// sink; until then the guard→reason mapping is code-review-gated.
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

  // MARK: - The other two arms of upstream's `dry_enabled` predicate (#1487)

  // These pin the *firing* path of the guards added at the b10327 pin, not
  // their success path: upstream disables DRY when ANY of `dry_multiplier != 0`
  // / `dry_base >= 1.0` / `dry_penalty_last_n != 0` fails, and does so by
  // returning a non-NULL `llama_sampler_init_empty("?dry")`. That handle seeds
  // and emits an ordinary `samplerDrySeeded` line, so without a Swift-side
  // guard an A/B arm set through either of these two levers runs inert while
  // every marker reads healthy. Each `#expect(… == nil)` fails if its guard is
  // dropped — a success-path assertion could not tell.

  @Test func resolveDisablesOnNonPositivePenaltyLastN() {
    // `0` reaches upstream's `dry_penalty_last_n != 0` arm directly. `-1` is
    // the case that changed meaning at the pin bump rather than staying
    // invalid — why it is no longer a sentinel: `DryConfig.resolve(environment:)`.
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_LAST_N": "0"]) == nil)
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_LAST_N": "-1"]) == nil)
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_LAST_N": "-512"]) == nil)
  }

  @Test func resolveDisablesOnSubUnityBase() {
    // Upstream requires `dry_base >= 1.0`; a base below it yields the same
    // silent `?dry` no-op as the two cases above.
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_BASE": "0.5"]) == nil)
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_BASE": "0"]) == nil)
  }

  @Test func resolveKeepsBoundaryValuesThatUpstreamAccepts() {
    // The negative control for the two guards above: the exact boundary values
    // upstream still enables on must survive, or the guards are over-broad.
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_LAST_N": "1"])?.penaltyLastN == 1)
    #expect(DryConfig.resolve(environment: ["PASTURA_DRY_BASE": "1.0"])?.base == 1.0)
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

  /// Pinning the exact set means a rename — or a fifth exit path — fails here
  /// instead of silently emitting a marker the `/model-eval` sweep has no
  /// expectation for. Why the vocabulary is load-bearing: `DryUnavailableReason`.
  ///
  /// `no-model` was retired at the b10327 pin: `llama_sampler_init_dry` no
  /// longer takes `n_ctx_train`, so the builder stopped needing a model
  /// pointer and the guard that emitted it no longer exists (#1487).
  @Test func dryUnavailableReasonsArePinnedAndDistinct() {
    let raws = DryUnavailableReason.allCases.map(\.rawValue)
    // A copy-pasted raw value would make two exit paths indistinguishable in
    // the sweep — the exact confusion the per-path markers exist to prevent.
    #expect(Set(raws).count == raws.count)
    #expect(Set(raws) == ["disabled", "no-seeds", "null-init", "no-grammar"])
  }

  /// Every field the `/model-eval` sweep reads must be on the line — dropping
  /// one must fail here. Why each is load-bearing: `drySeededLine`'s doc
  /// comment.
  @Test func drySeededLineCarriesEveryField() throws {
    let config = try #require(DryConfig.resolve(environment: [:]))
    let line = LlamaCppService.drySeededLine(
      seededTokenCount: 42, seedCount: 3,
      config: config, model: "test-model")

    #expect(line.hasPrefix("samplerDrySeeded "))
    #expect(line.contains("seededTokens=42"))
    #expect(line.contains("seeds=3"))
    #expect(!line.contains("nCtxTrain"))
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
