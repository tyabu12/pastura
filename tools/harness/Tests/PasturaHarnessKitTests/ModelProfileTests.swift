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
    #expect(profile.stopSequence == "<|im_end|>")
    #expect(profile.systemPromptSuffix == nil)
    // Gemma needs no assistant prefill — `<think>...` is Qwen-only.
    #expect(profile.assistantPrefix == nil)
    #expect(
      profile.expectedSHA256
        == "ac0069ebccd39925d836f24a88c0f0c858d20578c29b21ab7cedce66ee576845")
    #expect(profile.name == "Gemma 4 E2B (Q4_K_M)")
  }
}
