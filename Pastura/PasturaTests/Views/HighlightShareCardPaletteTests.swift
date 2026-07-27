import SwiftUI
import Testing

@testable import Pastura

/// Pins ``HighlightCardPalette``'s two families to **raw** `PasturaPalette`
/// values (ADR-028).
///
/// Why this suite exists: `HighlightShareCard` is the only sanctioned
/// fixed-appearance consumer in the app, and eight `Color.*` aliases are now
/// trait-resolving. If one creeps back into this palette, both families collapse
/// to "whatever appearance the renderer resolved" — and nothing else would
/// notice, because `ImageRenderer` output is asserted nowhere and ADR-009 rules
/// out snapshot tests. Comparing two `Color` values is logic extraction, which
/// ADR-009 permits.
///
/// A revert of the ADR-028 migration reddens every assertion below: `Color.ink`
/// and `PasturaPalette.ink.color` are not equal, because the former is
/// `Color(UIColor(dynamicProvider:))` and the latter `Color(.sRGB, …)`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HighlightShareCardPaletteTests {

  @Test func lightFamilyReadsRawLightTokens() {
    #expect(HighlightCardPalette.light.background == PasturaPalette.screenBackground.color)
    #expect(HighlightCardPalette.light.ink == PasturaPalette.ink.color)
    #expect(HighlightCardPalette.light.inkSecondary == PasturaPalette.inkSecondary.color)
    #expect(HighlightCardPalette.light.muted == PasturaPalette.muted.color)
    #expect(HighlightCardPalette.light.rule == PasturaPalette.rule.color)
    #expect(HighlightCardPalette.light.moss == PasturaPalette.moss.color)
  }

  @Test func darkFamilyReadsRawNightTokens() {
    #expect(HighlightCardPalette.dark.background == PasturaPalette.nightBackground.color)
    #expect(HighlightCardPalette.dark.ink == PasturaPalette.nightInk.color)
    #expect(HighlightCardPalette.dark.inkSecondary == PasturaPalette.nightInkSecondary.color)
    #expect(HighlightCardPalette.dark.muted == PasturaPalette.nightMuted.color)
    #expect(HighlightCardPalette.dark.rule == PasturaPalette.nightRule.color)
    #expect(HighlightCardPalette.dark.moss == PasturaPalette.nightMoss.color)
  }

  /// The property the card's whole appearance contract rests on: the two
  /// families must be *different*. A collapse (both reading the same
  /// trait-resolving alias) is exactly what this suite is here to catch, and it
  /// would not necessarily show up as a wrong value in either test above.
  @Test func theTwoFamiliesAreNotIdentical() {
    #expect(HighlightCardPalette.light.background != HighlightCardPalette.dark.background)
    #expect(HighlightCardPalette.light.ink != HighlightCardPalette.dark.ink)
    #expect(HighlightCardPalette.light.moss != HighlightCardPalette.dark.moss)
  }

  /// Guards the fixed-appearance contract directly: a raw palette value must
  /// resolve the same under both color schemes, unlike its paired alias.
  @Test func rawPaletteValuesAreAppearanceInvariant() {
    var light = EnvironmentValues()
    light.colorScheme = .light
    var dark = EnvironmentValues()
    dark.colorScheme = .dark

    let resolvedLight = HighlightCardPalette.dark.ink.resolve(in: light)
    let resolvedDark = HighlightCardPalette.dark.ink.resolve(in: dark)

    #expect(resolvedLight.red == resolvedDark.red)
    #expect(resolvedLight.green == resolvedDark.green)
    #expect(resolvedLight.blue == resolvedDark.blue)
  }
}
