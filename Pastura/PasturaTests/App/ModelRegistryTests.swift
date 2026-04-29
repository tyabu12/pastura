import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ModelRegistryTests {
  // Production catalog integrity
  @Test func catalog_hasExpectedModels() {
    let ids = ModelRegistry.catalog.map(\.id)
    #expect(ids == ["gemma-4-e2b-q4-k-m", "qwen-3-4b-q4-k-m"])
  }

  @Test func catalog_passesValidateNoCollisions() {
    // If this triggers the precondition, the test process crashes —
    // which is the correct signal. A successful run proves the catalog is valid.
    ModelRegistry.validateNoCollisions()
  }

  @Test func defaultInitialModelID_isGemma() {
    #expect(ModelRegistry.defaultInitialModelID == "gemma-4-e2b-q4-k-m")
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
      minRAM: ModelRegistry.qwen34B.minRAM,
      modelInfoURL: ModelRegistry.qwen34B.modelInfoURL,
      systemPromptSuffix: ModelRegistry.qwen34B.systemPromptSuffix
    )
    let reasons = ModelRegistry.findCollisions(in: [base, qwenAsGemmaFile])
    #expect(!reasons.isEmpty)
    #expect(reasons.contains(where: { $0.contains("fileName") }))
  }
}
