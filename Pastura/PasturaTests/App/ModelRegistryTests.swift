import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryTests {
  // Production catalog integrity. Order is asserted, not just membership: it is
  // display order for the picker / Settings / `ActiveModelChip`, and the legacy
  // Gemma build's trailing position is part of the ADD-and-keep shape (#1487).
  @Test func catalog_hasExpectedModels() {
    let ids = ModelRegistry.catalog.map(\.id)
    #expect(ids == ["gemma-4-e2b-qat-q4-k-xl", "qwen-3-4b-q4-k-m", "gemma-4-e2b-q4-k-m"])
  }

  /// Every `replacesModelID` names a real catalog entry.
  ///
  /// `validateNoCollisions` covers duplicate `id` / `fileName` only, so a typo
  /// here is caught by nothing at runtime — and it fails *silently and
  /// identically* in both consumers: `ModelManager.visibleCatalog` never hides
  /// the replaced entry, and `RecommendedModelStatus` never resolves the
  /// recommendation forward. The app then looks exactly as it would if the
  /// ADD-and-keep work had never been written.
  ///
  /// The non-empty assertion is the non-vacuity control: the sweep below is
  /// trivially true on an all-`nil` catalog, so without it this test would keep
  /// passing if the field were dropped from every descriptor.
  @Test func everyReplacesModelIDResolves() {
    let replaced = ModelRegistry.catalog.compactMap(\.replacesModelID)
    #expect(!replaced.isEmpty, "no descriptor declares replacesModelID — sweep would be vacuous")
    for id in replaced {
      #expect(
        ModelRegistry.lookup(id: id) != nil, "replacesModelID \"\(id)\" is not in the catalog")
    }
  }

  /// The replacement relation is resolvable in the forward direction too, from
  /// the id being replaced back to the entry taking over. Pins the QAT pairing
  /// specifically, since both consumers read it through this helper.
  @Test func replacement_resolvesTheQATPairing() {
    let replacement = ModelRegistry.replacement(
      for: ModelRegistry.gemma4E2B.id, in: ModelRegistry.catalog)
    #expect(replacement?.id == ModelRegistry.gemma4E2BQAT.id)
    #expect(
      ModelRegistry.replacement(for: ModelRegistry.qwen34B.id, in: ModelRegistry.catalog) == nil)
  }

  /// `recommendationTarget` picks the cheapest satisfying build, and on a tie
  /// the newer one. The both-`.ready` arm is the tie-break, and it is asserted
  /// here rather than through `RecommendedModelStatus.compute`: that classifier
  /// returns `.switchAvailable` either way, so its verdict cannot name which
  /// build was chosen — only the descriptor can.
  @Test func recommendationTarget_prefersTheReplacementOnATie() {
    let gemma = ModelRegistry.gemma4E2B.id
    let qat = ModelRegistry.gemma4E2BQAT.id

    let bothReady: [ModelID: ModelState] = [
      gemma: .ready(modelPath: "/tmp/g"), qat: .ready(modelPath: "/tmp/qat")
    ]
    #expect(ModelRegistry.recommendationTarget(for: gemma, state: bothReady)?.id == qat)

    let onlyDeclaredReady: [ModelID: ModelState] = [
      gemma: .ready(modelPath: "/tmp/g"), qat: .notDownloaded
    ]
    #expect(ModelRegistry.recommendationTarget(for: gemma, state: onlyDeclaredReady)?.id == gemma)

    let neitherReady: [ModelID: ModelState] = [gemma: .notDownloaded, qat: .notDownloaded]
    #expect(ModelRegistry.recommendationTarget(for: gemma, state: neitherReady)?.id == qat)

    // Forward-compat contract: `nil` only for an id in no catalog entry, which
    // is what `RecommendedModelStatus.unknownModel` keys on. `state` must not
    // introduce a second `nil` path.
    #expect(ModelRegistry.recommendationTarget(for: "future-model-v9", state: bothReady) == nil)
    #expect(ModelRegistry.recommendationTarget(for: gemma, state: [:])?.id == qat)
  }

  @Test func catalog_passesValidateNoCollisions() {
    // If this triggers the precondition, the test process crashes —
    // which is the correct signal. A successful run proves the catalog is valid.
    ModelRegistry.validateNoCollisions()
  }

  @Test func defaultInitialModelID_isQATGemma() {
    #expect(ModelRegistry.defaultInitialModelID == "gemma-4-e2b-qat-q4-k-xl")
  }

  /// `recommendedModelID` is the picker-UI "推奨" badge source. Semantically
  /// distinct from `defaultInitialModelID` (the resolve-order fallback), so
  /// we only assert it resolves to a registered descriptor — NOT equality
  /// with `defaultInitialModelID`. Asserting equality would create a brittle
  /// "which one do I update?" test when the two diverge (e.g., a future
  /// Qwen-recommended rollout).
  @Test func recommendedModelID_resolvesToRegisteredDescriptor() {
    #expect(ModelRegistry.lookup(id: ModelRegistry.recommendedModelID) != nil)
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

  @Test func gemmaQAT_taglineAndShortDisplayName_areSet() {
    #expect(!ModelRegistry.gemma4E2BQAT.tagline.isEmpty)
    #expect(ModelRegistry.gemma4E2BQAT.shortDisplayName != nil)
    // Distinct from the incumbent's short name, which is the whole point: both
    // are "Gemma 4 E2B", and the picker / Settings / `ActiveModelChip` render
    // `shortDisplayName ?? displayName`, so an equal pair is two identical rows.
    #expect(ModelRegistry.gemma4E2BQAT.shortDisplayName != ModelRegistry.gemma4E2B.shortDisplayName)
  }

  /// Integrity metadata read from the HuggingFace resolve URL's
  /// `X-Linked-Size` / `X-Linked-Etag` headers at the pinned commit. A silent
  /// edit here fails every user's download at the SHA-256 check rather than
  /// degrading, so it is pinned rather than code-review-gated.
  @Test func gemmaQAT_integrityMetadataMatchesFetchedValues() {
    #expect(ModelRegistry.gemma4E2BQAT.fileSize == 2_620_370_976)
    #expect(
      ModelRegistry.gemma4E2BQAT.sha256
        == "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889")
    // Same base model as `gemma4E2B`, so the same prompt-format contract — see
    // `gemma_hasNoAssistantPrefix` for why a non-nil prefix is a silent hazard.
    #expect(ModelRegistry.gemma4E2BQAT.assistantPrefix == nil)
    #expect(ModelRegistry.gemma4E2BQAT.systemPromptSuffix == nil)
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
      turnMarkers: ModelRegistry.qwen34B.turnMarkers,
      minRAM: ModelRegistry.qwen34B.minRAM,
      modelInfoURL: ModelRegistry.qwen34B.modelInfoURL,
      systemPromptSuffix: ModelRegistry.qwen34B.systemPromptSuffix
    )
    let reasons = ModelRegistry.findCollisions(in: [base, qwenAsGemmaFile])
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("fileName") }))
  }
}
