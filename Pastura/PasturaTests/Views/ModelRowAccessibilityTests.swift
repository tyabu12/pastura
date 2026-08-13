import Foundation
import Testing

@testable import Pastura

// `@MainActor` because the `character` mapping tests compare against
// `SheepAvatar.Character` (a default-MainActor enum) — its `Equatable`
// conformance is MainActor-isolated and the `==` operator isn't
// reachable from a nonisolated test context. The pure label-assembly
// tests don't need MainActor, but a single suite annotation is
// cheaper than splitting into two suites.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct ModelRowAccessibilityTests {

  // MARK: - Helpers

  /// Returns a descriptor that exercises the shortDisplayName + tagline
  /// path (production Gemma shape).
  func makeFullDescriptor() -> ModelDescriptor {
    ModelRegistry.gemma4E2B
  }

  /// Returns a descriptor with no shortDisplayName and an empty tagline
  /// — the "test fixture" shape that the row must degrade gracefully on.
  func makeBareDescriptor() -> ModelDescriptor {
    ModelDescriptor(
      id: "test-bare",
      displayName: "Bare Model (Q4_K_M)",
      vendor: "Test",
      vendorURL: URL(string: "https://example.com")!,
      downloadURL: URL(string: "https://example.com/bare.gguf")!,
      fileName: "bare.gguf",
      fileSize: 1_000_000_000,
      sha256: "",
      stopSequence: "<|im_end|>",
      turnMarkers: .chatML,
      minRAM: 6_500_000_000,
      modelInfoURL: URL(string: "https://example.com")!,
      systemPromptSuffix: nil
    )
  }

  // MARK: - displayName + size contract

  /// Bug-shape: revert the label assembly to "just the displayName" and
  /// this test fails. Size is load-bearing for VoiceOver (users need to
  /// hear the ~3 GB cost before tapping download), so it MUST appear
  /// in the row's combined a11y label.
  @Test func label_containsDisplayName_andFormattedSize() {
    let descriptor = makeFullDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: false)

    // shortDisplayName wins when available (Q4_K_M-free).
    #expect(label.contains("Gemma 4 E2B"))
    #expect(label.contains(formattedSize))
  }

  /// `shortDisplayName == nil` falls back to `displayName`. Production
  /// descriptors all set shortDisplayName explicitly; bare/test
  /// descriptors don't. Both must still produce a usable label.
  @Test func label_fallsBackToDisplayName_whenShortMissing() {
    let descriptor = makeBareDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: false)

    #expect(label.contains("Bare Model (Q4_K_M)"))
    #expect(label.contains(formattedSize))
  }

  // MARK: - Recommended tag

  /// The visible "推奨" chip is `.accessibilityHidden(true)` so VoiceOver
  /// only hears it via the combined row label. `isRecommended: true`
  /// must surface "Recommended" in the assembled string.
  @Test func label_includesRecommended_whenIsRecommendedTrue() {
    let descriptor = makeFullDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: true)

    #expect(label.contains("Recommended"))
  }

  @Test func label_omitsRecommended_whenIsRecommendedFalse() {
    let descriptor = makeFullDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: false)

    #expect(!label.contains("Recommended"))
  }

  // MARK: - Tagline gating

  /// Empty tagline must NOT inject an empty fragment into the label —
  /// otherwise VoiceOver pauses mid-utterance for the empty join
  /// separator, which sounds broken.
  @Test func label_omitsTagline_whenEmpty() {
    let descriptor = makeBareDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: false)

    // No double-comma artifact from joining empty fragments.
    #expect(!label.contains(", ,"))
    // No trailing comma either.
    #expect(!label.hasSuffix(","))
  }

  /// Production descriptors with non-empty tagline include it in the
  /// label — gives VoiceOver users the same context sighted users see.
  @Test func label_includesTagline_whenNonEmpty() {
    let descriptor = makeFullDescriptor()
    let formattedSize = ModelRow.formattedFileSize(descriptor.fileSize)
    let label = ModelRow.accessibilityLabel(
      for: descriptor, sizeFormatted: formattedSize, isRecommended: false)

    #expect(label.contains(descriptor.tagline))
  }

  // MARK: - character mapping

  @Test func character_mapsGemmaToAlice() {
    #expect(ModelRow.character(for: ModelRegistry.gemma4E2B) == .alice)
  }

  @Test func character_mapsQwenToBob() {
    #expect(ModelRow.character(for: ModelRegistry.qwen34B) == .bob)
  }

  /// Unknown descriptor falls through to the existing `forAgent` name-
  /// based resolver. The mapping is deterministic but bucket-dependent;
  /// we only assert it returns *some* character without crashing.
  @Test func character_fallsBack_forUnknownDescriptor() {
    let bare = makeBareDescriptor()
    let resolved = ModelRow.character(for: bare)
    #expect(SheepAvatar.Character.allCases.contains(resolved))
  }
}
