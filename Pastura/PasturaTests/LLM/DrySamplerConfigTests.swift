import Testing

@testable import Pastura

/// Unit tests for the simulator-runnable, inference-free parts of the #1105
/// DRY anti-repetition sampler: `DryConfig.resolve(environment:)` (the shipped
/// default + harness A/B override logic) and `withArrayOfCStrings` (the
/// C-string pointer-lifetime helper that feeds `llama_sampler_init_dry`).
///
/// The seeding + apply paths (`buildAndSeedDrySampler`, `fillApplyAndSelect`)
/// require real inference and are unrunnable on the simulator (PR #463) — they
/// are validated on device / via the pastura-harness A/B (#1105), not here.
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
}
