import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct ModelDescriptorTests {
  // MARK: - Helpers

  /// Returns a valid `ModelDescriptor` for use across multiple tests.
  func makeDescriptor(id: ModelID = "gemma-4-e2b-q4-k-m") -> ModelDescriptor {
    ModelDescriptor(
      id: id,
      displayName: "Gemma 4 E2B (Q4_K_M)",
      vendor: "Google",
      vendorURL: URL(string: "https://deepmind.google")!,
      downloadURL: URL(string: "https://example.com/gemma-4-E2B-it-Q4_K_M.gguf")!,
      fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
      fileSize: 3_100_000_000,
      sha256: "abc123def456",
      stopSequence: "<|im_end|>",
      minRAM: 6_000_000_000,
      modelInfoURL: URL(string: "https://huggingface.co/google/gemma-4-e2b")!,
      systemPromptSuffix: nil
    )
  }

  // MARK: - isValidFileName

  @Test func isValidFileName_acceptsValidNames() {
    #expect(ModelDescriptor.isValidFileName("gemma-4-E2B-it-Q4_K_M.gguf"))
    #expect(ModelDescriptor.isValidFileName("qwen3-4b.gguf"))
    #expect(ModelDescriptor.isValidFileName("a.gguf"))
    #expect(ModelDescriptor.isValidFileName("UPPERCASE.gguf"))
    #expect(ModelDescriptor.isValidFileName("dots.in.name.gguf"))
    #expect(ModelDescriptor.isValidFileName("with_underscores.gguf"))
  }

  @Test func isValidFileName_rejectsInvalidNames() {
    #expect(!ModelDescriptor.isValidFileName(""))
    #expect(!ModelDescriptor.isValidFileName("no_extension"))
    #expect(!ModelDescriptor.isValidFileName("wrong_extension.bin"))
    #expect(!ModelDescriptor.isValidFileName("../escape.gguf"))
    #expect(!ModelDescriptor.isValidFileName("has/slash.gguf"))
    #expect(!ModelDescriptor.isValidFileName("has space.gguf"))
    #expect(!ModelDescriptor.isValidFileName("has:colon.gguf"))
    // No base name — just the extension
    #expect(!ModelDescriptor.isValidFileName(".gguf"))
  }

  // MARK: - Construction

  @Test func construction_setsAllFields() {
    let vendorURL = URL(string: "https://deepmind.google")!
    let downloadURL = URL(string: "https://example.com/gemma-4-E2B-it-Q4_K_M.gguf")!
    let modelInfoURL = URL(string: "https://huggingface.co/google/gemma-4-e2b")!

    let descriptor = ModelDescriptor(
      id: "gemma-4-e2b-q4-k-m",
      displayName: "Gemma 4 E2B (Q4_K_M)",
      shortDisplayName: "Gemma 4 E2B",
      vendor: "Google",
      vendorURL: vendorURL,
      downloadURL: downloadURL,
      fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
      fileSize: 3_100_000_000,
      sha256: "abc123def456",
      stopSequence: "<|im_end|>",
      minRAM: 6_000_000_000,
      modelInfoURL: modelInfoURL,
      systemPromptSuffix: "/no_think",
      assistantPrefix: "<think>\n\n</think>\n\n",
      tagline: "Balanced choice."
    )

    #expect(descriptor.id == "gemma-4-e2b-q4-k-m")
    #expect(descriptor.displayName == "Gemma 4 E2B (Q4_K_M)")
    #expect(descriptor.shortDisplayName == "Gemma 4 E2B")
    #expect(descriptor.vendor == "Google")
    #expect(descriptor.vendorURL == vendorURL)
    #expect(descriptor.downloadURL == downloadURL)
    #expect(descriptor.fileName == "gemma-4-E2B-it-Q4_K_M.gguf")
    #expect(descriptor.fileSize == 3_100_000_000)
    #expect(descriptor.sha256 == "abc123def456")
    #expect(descriptor.stopSequence == "<|im_end|>")
    #expect(descriptor.minRAM == 6_000_000_000)
    #expect(descriptor.modelInfoURL == modelInfoURL)
    #expect(descriptor.systemPromptSuffix == "/no_think")
    #expect(descriptor.assistantPrefix == "<think>\n\n</think>\n\n")
    #expect(descriptor.tagline == "Balanced choice.")
  }

  /// `assistantPrefix` is optional with a `nil` default to keep construction
  /// ergonomic for the common Gemma-shaped case. Verifies that omitting the
  /// argument lands as `nil`, not as a fault.
  @Test func construction_assistantPrefixDefaultsToNil() {
    let descriptor = makeDescriptor()
    #expect(descriptor.assistantPrefix == nil)
  }

  /// `tagline` defaults to empty so test fixtures and historical callsites
  /// don't need to thread it through. Production descriptors set it explicitly
  /// in `ModelRegistry`.
  @Test func construction_taglineDefaultsToEmpty() {
    let descriptor = makeDescriptor()
    #expect(descriptor.tagline.isEmpty)
  }

  /// `shortDisplayName` defaults to `nil` for the same reason; UI sites that
  /// need a Q4_K_M-free label resolve to `displayName` when nil.
  @Test func construction_shortDisplayNameDefaultsToNil() {
    let descriptor = makeDescriptor()
    #expect(descriptor.shortDisplayName == nil)
  }

  // MARK: - Hashable

  @Test func hashable_equalDescriptorsHashEqual() {
    let lhs = makeDescriptor()
    let rhs = makeDescriptor()
    #expect(lhs == rhs)
    #expect(lhs.hashValue == rhs.hashValue)
  }

  @Test func hashable_differentIDsHashDiffer() {
    let lhs = makeDescriptor(id: "model-a")
    let rhs = makeDescriptor(id: "model-b")
    #expect(lhs != rhs)
  }
}
