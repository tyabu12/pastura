import Testing

@testable import PasturaHarnessKit

@Suite(.timeLimit(.minutes(1)))
struct ModelProfileTests {
  /// Drift guard against `App/ModelRegistry.gemma4E2B` (the registry is
  /// App-layer, outside this package — a cross-reference comment alone is
  /// not drift-proof). If this fails, the app registry changed: update
  /// `ModelProfile.gemma4E2B` to match, deliberately.
  @Test func gemmaProfilePinsMatchAppRegistry() {
    let profile = ModelProfile.gemma4E2B
    #expect(profile.id == "gemma-4-e2b-q4-k-m")
    #expect(profile.stopSequence == "<|im_end|>")
    #expect(profile.systemPromptSuffix == nil)
    // Gemma needs no assistant prefill — `<think>...` is Qwen-only.
    #expect(profile.assistantPrefix == nil)
    #expect(
      profile.expectedSHA256
        == "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845")
    #expect(profile.name == "Gemma 4 E2B (Q4_K_M)")
    #expect(profile.expectedFileName == "gemma-4-E2B-it-Q4_K_M.gguf")
  }

  /// Drift guard against `App/ModelRegistry.qwen34B` (the registry is
  /// App-layer, outside this package — a cross-reference comment alone is
  /// not drift-proof). If this fails, the app registry changed: update
  /// `ModelProfile.qwen34B` to match, deliberately.
  @Test func qwenProfilePinsMatchAppRegistry() {
    let profile = ModelProfile.qwen34B
    #expect(profile.id == "qwen-3-4b-q4-k-m")
    #expect(profile.name == "Qwen 3 4B (Q4_K_M)")
    #expect(profile.stopSequence == "<|im_end|>")
    #expect(profile.systemPromptSuffix == "/no_think")
    #expect(profile.assistantPrefix == "<think>\n\n</think>\n\n")
    #expect(profile.expectedFileName == "Qwen3-4B-Q4_K_M.gguf")
    #expect(
      profile.expectedSHA256
        == "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5")
  }

  @Test func namedLooksUpKnownProfilesByID() {
    #expect(ModelProfile.named("gemma-4-e2b-q4-k-m") == .gemma4E2B)
    #expect(ModelProfile.named("qwen-3-4b-q4-k-m") == .qwen34B)
    #expect(ModelProfile.named("bogus") == nil)
  }

  @Test func mismatchWarningIsNilOnExactFileNameMatch() {
    let warning = ModelProfile.qwen34B.mismatchWarning(
      forModelPath: "/Users/x/Models/Qwen3-4B-Q4_K_M.gguf")
    #expect(warning == nil)
  }

  @Test func mismatchWarningIsNilOnCaseVariedFileName() {
    let warning = ModelProfile.qwen34B.mismatchWarning(
      forModelPath: "/Users/x/Models/qwen3-4b-q4_k_m.gguf")
    #expect(warning == nil)
  }

  @Test func mismatchWarningFiresOnMismatchedFileName() {
    let warning = ModelProfile.qwen34B.mismatchWarning(
      forModelPath: "/Users/x/Models/gemma-4-E2B-it-Q4_K_M.gguf")
    #expect(warning != nil)
    #expect(warning?.contains("gemma-4-E2B-it-Q4_K_M.gguf") == true)
    #expect(warning?.contains("qwen-3-4b-q4-k-m") == true)
  }
}
