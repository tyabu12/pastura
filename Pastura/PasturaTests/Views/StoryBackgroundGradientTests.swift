import Testing

@testable import Pastura

/// Change-detector tripwire for the Instagram Stories background gradient
/// endpoints (``StoryBackgroundGradient``). These mirror the source-of-truth
/// moss palette tokens **by design**. A failure here does NOT mean a bug was
/// found: it means a code-review-gated visual constant drifted (the moss
/// palette or its hex derivation changed), and the editor must confirm the
/// change passed code review before updating the expected value. See #1083.
@Suite("StoryBackgroundGradient", .timeLimit(.minutes(1)))
@MainActor
struct StoryBackgroundGradientTests {

  @Test func hexStringRoundTripsKnownPaletteTokens() {
    #expect(PasturaPalette.moss.hexString == "#8A9A6C")
    #expect(PasturaPalette.mossDark.hexString == "#6B7852")
  }

  @Test func gradientEndpointsMatchMossPalette() {
    #expect(StoryBackgroundGradient.topHex == "#8A9A6C")
    #expect(StoryBackgroundGradient.bottomHex == "#6B7852")
  }
}
