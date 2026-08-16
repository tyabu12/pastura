import PasturaCore
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
    #expect(profile.turnMarkers == ChatTurnMarkers(start: "<|turn>", end: "<turn|>"))
    // Same deliberate divergence the app registry carries: the generation-side
    // sentinel is a ChatML string absent from Gemma's vocabulary, so that path
    // is inert; repointing it is deferred to #1451, not an oversight (#1422).
    #expect(profile.stopSequence != profile.turnMarkers.end)
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
    #expect(profile.turnMarkers == .chatML)
    #expect(profile.systemPromptSuffix == "/no_think")
    #expect(profile.assistantPrefix == "<think>\n\n</think>\n\n")
    #expect(profile.expectedFileName == "Qwen3-4B-Q4_K_M.gguf")
    #expect(
      profile.expectedSHA256
        == "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5")
  }

  /// Pins the Sarashina 2.2 3B Stage-0 candidate's investigated fields.
  /// Unlike the gemma/qwen tests above, there is **no** `App/ModelRegistry`
  /// entry to guard against yet — Sarashina is a candidate under the
  /// `/model-eval` Mac-filter gate, not a shipped model. This pins the
  /// values investigated at Stage 0; reconcile them with the eventual
  /// `ModelDescriptor` at Gate-2 registration (see #979).
  @Test func sarashinaProfilePinsFields() {
    let profile = ModelProfile.sarashina223B
    #expect(profile.id == "sarashina-2-2-3b-q4-k-m")
    #expect(profile.name == "Sarashina 2.2 3B (Q4_K_M)")
    // Plain eos stop; no thinking-mode workaround (contrast Qwen #366).
    #expect(profile.stopSequence == "</s>")
    #expect(profile.turnMarkers == ChatTurnMarkers(start: "<|assistant|>", end: "</s>"))
    #expect(profile.systemPromptSuffix == nil)
    #expect(profile.assistantPrefix == nil)
    #expect(profile.expectedFileName == "sarashina2.2-3b-instruct-v0.1-Q4_K_M.gguf")
    #expect(
      profile.expectedSHA256
        == "d96f4d98eb528df26e8bc09ab81a1d165be4fce67616739e65980bed9038f0f2")
  }

  /// Drift guard against `App/ModelRegistry.gemma4E2BQAT` (the registry is
  /// App-layer, outside this package — a cross-reference comment alone is
  /// not drift-proof). If this fails, the app registry changed: update
  /// `ModelProfile.gemma4E2BQAT` to match, deliberately.
  @Test func gemmaQATProfilePinsMatchAppRegistry() {
    let profile = ModelProfile.gemma4E2BQAT
    #expect(profile.id == "gemma-4-e2b-qat-q4-k-xl")
    #expect(profile.name == "Gemma 4 E2B (QAT)")
    #expect(profile.stopSequence == "<|im_end|>")
    #expect(profile.turnMarkers == ChatTurnMarkers(start: "<|turn>", end: "<turn|>"))
    #expect(profile.systemPromptSuffix == nil)
    #expect(profile.assistantPrefix == nil)
    #expect(profile.expectedFileName == "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf")
    #expect(
      profile.expectedSHA256
        == "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889")
  }

  @Test func namedLooksUpKnownProfilesByID() {
    #expect(ModelProfile.named("gemma-4-e2b-q4-k-m") == .gemma4E2B)
    #expect(ModelProfile.named("qwen-3-4b-q4-k-m") == .qwen34B)
    #expect(ModelProfile.named("sarashina-2-2-3b-q4-k-m") == .sarashina223B)
    #expect(ModelProfile.named("gemma-4-e2b-qat-q4-k-xl") == .gemma4E2BQAT)
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
