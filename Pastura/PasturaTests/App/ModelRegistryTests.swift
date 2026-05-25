import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryTests {
  // Production catalog integrity
  @Test func catalog_hasExpectedModels() {
    let ids = ModelRegistry.catalog.map(\.id)
    #expect(ids == ["gemma-4-e2b-q4-k-m", "qwen-3-4b-q4-k-m", "gemma-3-1b-it-q4-k-m"])
  }

  @Test func catalog_passesValidateNoCollisions() {
    // If this triggers the precondition, the test process crashes —
    // which is the correct signal. A successful run proves the catalog is valid.
    ModelRegistry.validateNoCollisions()
  }

  // MARK: - Tier-aware recommendation / default-initial APIs (#477)
  //
  // The `(for: physicalMemory)` form replaces the previous `static let`
  // properties so the picker / `ModelManager.resolveInitialActiveID` can
  // route 6 GB tier devices to the lighter Gemma 3 1B descriptor.
  //
  // `recommendedModelID` and `defaultInitialModelID` are kept identity-
  // distinct (separate functions) so future schemas — multi-recommended
  // rollouts, A/B-tested defaults, conditional recommendation by device
  // class — can diverge without reshaping the fallback. Tests assert each
  // independently against the registered catalog rather than equality.

  @Test func recommendedModelID_for6GBTier_returnsGemma31B() {
    #expect(ModelRegistry.recommendedModelID(for: 5_500_000_000) == ModelRegistry.gemma31B.id)
  }

  @Test func recommendedModelID_for8GBTier_returnsGemma4() {
    #expect(
      ModelRegistry.recommendedModelID(for: 8 * 1024 * 1024 * 1024)
        == ModelRegistry.gemma4E2B.id)
  }

  /// The 6.5 GB shared floor that gates Gemma 4 / Qwen 3 is exclusive on
  /// the lower bound (`..<6_500_000_000`): exactly 6.5 GB physical routes
  /// to the 8 GB+ tier, anything strictly below routes to the 6 GB tier.
  @Test func recommendedModelID_atBoundary_routesByExclusiveLowerBound() {
    #expect(
      ModelRegistry.recommendedModelID(for: 6_500_000_000) == ModelRegistry.gemma4E2B.id)
    #expect(
      ModelRegistry.recommendedModelID(for: 6_499_999_999) == ModelRegistry.gemma31B.id)
  }

  @Test func defaultInitialModelID_for6GBTier_returnsGemma31B() {
    #expect(ModelRegistry.defaultInitialModelID(for: 5_500_000_000) == ModelRegistry.gemma31B.id)
  }

  @Test func defaultInitialModelID_for8GBTier_returnsGemma4() {
    #expect(
      ModelRegistry.defaultInitialModelID(for: 8 * 1024 * 1024 * 1024)
        == ModelRegistry.gemma4E2B.id)
  }

  /// Contract test — whatever the API returns must be in the catalog,
  /// regardless of device tier. Replaces the previous tier-agnostic
  /// `recommendedModelID_resolvesToRegisteredDescriptor` (the API now
  /// requires a tier hint, so a tier-spread cover is the natural form).
  @Test func recommendedModelID_alwaysResolvesToRegisteredDescriptor() {
    let coverage: [UInt64] = [
      4 * 1024 * 1024 * 1024,  // 4 GB (sub-tier — still lands on a real descriptor)
      6 * 1024 * 1024 * 1024,  // 6 GB tier
      8 * 1024 * 1024 * 1024,  // 8 GB+ tier
      12 * 1024 * 1024 * 1024  // 12 GB (iPhone 17 Pro / Air)
    ]
    for ram in coverage {
      #expect(ModelRegistry.lookup(id: ModelRegistry.recommendedModelID(for: ram)) != nil)
      #expect(ModelRegistry.lookup(id: ModelRegistry.defaultInitialModelID(for: ram)) != nil)
    }
  }

  /// Gemma's UI metadata: tagline is set (non-empty) and shortDisplayName
  /// strips the `(Q4_K_M)` quantization tag so the picker / settings can
  /// show "Gemma 4 E2B" without exposing the quantization format.
  @Test func gemma_taglineAndShortDisplayName_areSet() {
    #expect(!ModelRegistry.gemma4E2B.tagline.isEmpty)
    #expect(ModelRegistry.gemma4E2B.shortDisplayName != nil)
    #expect(ModelRegistry.gemma4E2B.shortDisplayName?.contains("Q4_K_M") == false)
  }

  @Test func qwen_taglineAndShortDisplayName_areSet() {
    #expect(!ModelRegistry.qwen34B.tagline.isEmpty)
    #expect(ModelRegistry.qwen34B.shortDisplayName != nil)
    #expect(ModelRegistry.qwen34B.shortDisplayName?.contains("Q4_K_M") == false)
  }

  @Test func gemma3_taglineAndShortDisplayName_areSet() {
    #expect(!ModelRegistry.gemma31B.tagline.isEmpty)
    #expect(ModelRegistry.gemma31B.shortDisplayName != nil)
    #expect(ModelRegistry.gemma31B.shortDisplayName?.contains("Q4_K_M") == false)
  }

  /// Gemma 3 1B IT is a Phase 2 lower-tier addition (#477) for 6 GB RAM
  /// devices. `minRAM` MUST be below the 6.5 GB shared floor used by the
  /// heavier Gemma 4 / Qwen 3 entries — otherwise the per-descriptor gating
  /// migration (Plan Item 4) would still leave 6 GB devices stuck on
  /// `.unsupportedDevice`. The exact value (5.5 GB) leaves OS-overhead
  /// headroom and is tunable from on-device PoC measurements.
  @Test func gemma3_minRAM_belowSharedFloor() {
    #expect(ModelRegistry.gemma31B.minRAM < 6_500_000_000)
  }

  /// Gemma 3 has no thinking-mode token (cf. Qwen 3's `<think>`-driven
  /// crash #366), so it must NOT carry an `assistantPrefix`. A non-nil
  /// prefix here would silently change Gemma 3's generation surface.
  @Test func gemma3_hasNoAssistantPrefix() {
    #expect(ModelRegistry.gemma31B.assistantPrefix == nil)
  }

  /// PoC draft sentinel canary (#477). The PoC flow downloads the real
  /// GGUF on a 6 GB device, measures `fileSize` and `sha256`, and replaces
  /// these placeholders before the PR is moved out of draft. Until then:
  ///
  /// - `fileSize == 0` trips `ModelManager.computeState`'s
  ///   `descriptor.fileSize > 0` guard (no size-mismatch deletion).
  /// - `sha256 == ""` trips `ModelManager.verifyDownloadIntegrity`'s
  ///   `!descriptor.sha256.isEmpty` guard (integrity check skipped).
  ///
  /// `ModelRegistry.validateProductionReadiness()` (added in the next
  /// commit) traps these sentinels in Release builds. When PoC values
  /// land, REPLACE this test with `gemma3_integrityMetadataMatchesFetchedValues`
  /// mirroring the Gemma 4 / Qwen 3 integrity assertions above.
  @Test func gemma3_draftSentinelPlaceholders_pendingPoC() {
    #expect(ModelRegistry.gemma31B.fileSize == 0)
    #expect(ModelRegistry.gemma31B.sha256 == "")
  }

  // Gemma upgrade-compat contract: filename must match the legacy constant
  // currently in ModelManager.swift. Changing this value without a migration
  // would force existing TestFlight users to re-download 3.1 GB.
  @Test func gemma_fileName_matchesLegacyConstant() {
    #expect(ModelRegistry.gemma4E2B.fileName == "gemma-4-E2B-it-Q4_K_M.gguf")
  }

  @Test func gemma_integrityMetadataMatchesLegacyConstants() {
    #expect(ModelRegistry.gemma4E2B.fileSize == 3_106_735_776)
    #expect(
      ModelRegistry.gemma4E2B.sha256
        == "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845")
  }

  @Test func qwen_integrityMetadataMatchesFetchedValues() {
    #expect(ModelRegistry.qwen34B.fileSize == 2_497_280_256)
    #expect(
      ModelRegistry.qwen34B.sha256
        == "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5")
    #expect(ModelRegistry.qwen34B.systemPromptSuffix == "/no_think")
    // Issue #366 — without this prefill, Qwen 3 emits `<think>` as its first
    // generated token and the GBNF grammar sampler crashes via uncaught C++
    // exception. The exact string is load-bearing (matches the Qwen 3 Jinja
    // chat template's `enable_thinking=false` output).
    #expect(ModelRegistry.qwen34B.assistantPrefix == "<think>\n\n</think>\n\n")
  }

  /// Gemma must NOT carry an `assistantPrefix` — the bridge between the
  /// chat template and Gemma's training assumes the assistant turn starts
  /// empty. A non-nil prefix here would silently change Gemma's generation
  /// surface.
  @Test func gemma_hasNoAssistantPrefix() {
    #expect(ModelRegistry.gemma4E2B.assistantPrefix == nil)
  }

  // findCollisions testability — covers the uniqueness check without
  // relying on a preconditioned call site.
  @Test func findCollisions_emptyForProductionCatalog() {
    #expect(ModelRegistry.findCollisions(in: ModelRegistry.catalog).isEmpty)
  }

  @Test func findCollisions_detectsDuplicateIDs() {
    let duplicated = [ModelRegistry.gemma4E2B, ModelRegistry.gemma4E2B]
    let reasons = ModelRegistry.findCollisions(in: duplicated)
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("id") }))
  }

  // lookup helper
  @Test func lookupReturnsDescriptorForKnownID() {
    #expect(ModelRegistry.lookup(id: ModelRegistry.gemma4E2B.id)?.id == ModelRegistry.gemma4E2B.id)
    #expect(ModelRegistry.lookup(id: ModelRegistry.qwen34B.id)?.id == ModelRegistry.qwen34B.id)
  }

  @Test func lookupReturnsNilForUnknownID() {
    #expect(ModelRegistry.lookup(id: "no-such-model") == nil)
  }

  // MARK: - validateProductionReadiness (#477)
  //
  // Sentinel detection for PoC-draft descriptors. The wrapper
  // `validateProductionReadiness()` is `precondition`-based and only
  // invoked from `PasturaApp.initialize` under `#if !DEBUG`, so it
  // cannot be tested directly here without crashing the test process.
  // We test `findSentinels` (the pure helper) instead, mirroring the
  // `findCollisions` / `validateNoCollisions` split above.

  @Test func findSentinels_detectsZeroFileSize() {
    let sentinel = ModelDescriptor(
      id: "test-sentinel-filesize",
      displayName: "Test",
      vendor: "Test",
      vendorURL: ModelRegistry.gemma4E2B.vendorURL,
      downloadURL: ModelRegistry.gemma4E2B.downloadURL,
      fileName: "test-sentinel-filesize.gguf",
      fileSize: 0,
      sha256: "abc",
      stopSequence: "<|im_end|>",
      minRAM: 6_500_000_000,
      modelInfoURL: ModelRegistry.gemma4E2B.modelInfoURL,
      systemPromptSuffix: nil
    )
    let reasons = ModelRegistry.findSentinels(in: [sentinel])
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("fileSize") }))
  }

  @Test func findSentinels_detectsEmptySha256() {
    let sentinel = ModelDescriptor(
      id: "test-sentinel-sha",
      displayName: "Test",
      vendor: "Test",
      vendorURL: ModelRegistry.gemma4E2B.vendorURL,
      downloadURL: ModelRegistry.gemma4E2B.downloadURL,
      fileName: "test-sentinel-sha.gguf",
      fileSize: 100,
      sha256: "",
      stopSequence: "<|im_end|>",
      minRAM: 6_500_000_000,
      modelInfoURL: ModelRegistry.gemma4E2B.modelInfoURL,
      systemPromptSuffix: nil
    )
    let reasons = ModelRegistry.findSentinels(in: [sentinel])
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("sha256") }))
  }

  @Test func findSentinels_emptyForConcreteDescriptors() {
    // Gemma 4 + Qwen 3 both carry concrete fileSize / sha256.
    let reasons = ModelRegistry.findSentinels(in: [
      ModelRegistry.gemma4E2B, ModelRegistry.qwen34B
    ])
    #expect(reasons.isEmpty)
  }

  /// Canary for the PoC discipline: the production catalog currently
  /// carries Gemma 3 1B's sentinel placeholders. When PoC fills in
  /// real values, this test flips to assert `reasons.isEmpty` and
  /// `validateProductionReadiness()` becomes safe to call against the
  /// production catalog in all build configs.
  @Test func findSentinels_currentCatalogHasGemma3PoCSentinels() {
    let reasons = ModelRegistry.findSentinels(in: ModelRegistry.catalog)
    #expect(reasons.contains(where: { $0.contains("gemma-3-1b-it-q4-k-m") }))
  }

  @Test func findCollisions_detectsDuplicateFileNames() {
    // Fabricate two descriptors with same fileName but different ids
    let base = ModelRegistry.gemma4E2B
    // Reconstruct Qwen but forced to use Gemma's fileName → fileName collision
    let qwenAsGemmaFile = ModelDescriptor(
      id: ModelRegistry.qwen34B.id,
      displayName: ModelRegistry.qwen34B.displayName,
      vendor: ModelRegistry.qwen34B.vendor,
      vendorURL: ModelRegistry.qwen34B.vendorURL,
      downloadURL: ModelRegistry.qwen34B.downloadURL,
      fileName: ModelRegistry.gemma4E2B.fileName,  // ← collision
      fileSize: ModelRegistry.qwen34B.fileSize,
      sha256: ModelRegistry.qwen34B.sha256,
      stopSequence: ModelRegistry.qwen34B.stopSequence,
      minRAM: ModelRegistry.qwen34B.minRAM,
      modelInfoURL: ModelRegistry.qwen34B.modelInfoURL,
      systemPromptSuffix: ModelRegistry.qwen34B.systemPromptSuffix
    )
    let reasons = ModelRegistry.findCollisions(in: [base, qwenAsGemmaFile])
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("fileName") }))
  }
}
