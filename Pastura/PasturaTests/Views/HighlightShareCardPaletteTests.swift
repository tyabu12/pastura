import SwiftUI
import Testing

@testable import Pastura

/// Pins ``HighlightCardPalette``'s two families to **raw** `PasturaPalette`
/// values (ADR-028).
///
/// Why this suite exists: `HighlightShareCard` is the only sanctioned
/// fixed-appearance consumer in the app, and 67 `Color.*` aliases are now
/// trait-resolving. If one creeps back into this palette, both families collapse
/// to whatever the render environment resolved — and nothing else would notice,
/// because `ImageRenderer` output is asserted nowhere and ADR-009 rules out
/// snapshot tests. Comparing two `Color` values is logic extraction, which
/// ADR-009 permits.
///
/// **What that collapse costs, measured in #1337:** not a dark export silently
/// rendering light — the render environment is the `colorScheme` the caller
/// injects, so an alias would still resolve to the *requested* appearance. It
/// costs `light` and `dark` becoming the same thing, so the caller's choice stops
/// having any effect, and it puts the export's correctness on a platform
/// behaviour Apple owns rather than on sRGB values this repo pins. See ADR-028
/// § Amendment 2026-08-06 (#1337).
///
/// ``SheepAvatarPaletteTests`` guards the same contract one level down, for
/// the avatar this card draws — `HighlightCardPalette` covers six tokens and
/// none of them is §2.5.
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

  /// Independent trigger the two tests above do NOT have. Alias creep is not it —
  /// that reddens `lightFamilyReadsRawLightTokens` directly (verified by negative
  /// control). What only this test catches is a **token-value** collapse: if a
  /// future retune gave `nightInk` the same hex as `ink`, both tests above would
  /// still pass while the card's two families became visually identical.
  @Test func theTwoFamiliesAreNotIdentical() {
    #expect(HighlightCardPalette.light.background != HighlightCardPalette.dark.background)
    #expect(HighlightCardPalette.light.ink != HighlightCardPalette.dark.ink)
    #expect(HighlightCardPalette.light.moss != HighlightCardPalette.dark.moss)
  }

  /// Guards the fixed-appearance contract on **every** slot of both families: a
  /// raw palette value resolves identically under either scheme, unlike its
  /// paired alias. This is the assertion with a real trigger — alias creep
  /// resolves differently across schemes and reddens here.
  ///
  /// Slots come from `Mirror`, not a hand list: the previous version named the
  /// six by hand, so a seventh stored property reading `Color.ink` passed every
  /// assertion in this file. The two pins below are what keep the reflection
  /// honest — `expectedSlotCount` so the arm cannot go vacuous if the slots
  /// ever become computed, and the `childCount` comparison so a colour-bearing
  /// slot typed `AnyShapeStyle` / `LinearGradient` reddens instead of being
  /// dropped by `as? Color`. Both are exercised by
  /// ``DesignTokensTests/reflectionReportsAPairedAliasSlotAsVarying`` and
  /// ``DesignTokensTests/reflectionDoesNotSilentlySkipANonColorSlot``.
  @Test func rawPaletteValuesAreAppearanceInvariant() {
    let expectedSlotCount = 6
    let families = [HighlightCardPalette.light, HighlightCardPalette.dark]
    for family in families {
      let reflected = reflectedColorSlots(of: family)
      #expect(reflected.childCount == expectedSlotCount)
      #expect(reflected.colors.count == reflected.childCount)
      for slot in reflected.colors {
        #expect(resolvesIdenticallyAcrossSchemes(slot))
      }
    }
  }

  /// Positive control for `rawPaletteValuesAreAppearanceInvariant`, added with
  /// ADR-028 slice 3.
  ///
  /// That test asserts a *negative* — "these do not vary" — which a broken
  /// comparison satisfies just as well. This feeds the same helper the paired
  /// aliases the palette deliberately avoids, and requires it to report them as
  /// varying. Without it the invariance assertion could pass by measuring
  /// nothing. (The shared helper also compares `opacity`, which this suite's
  /// previous inline version did not.)
  @Test func thePairedAliasesThisPaletteAvoidsDoVaryAcrossSchemes() {
    let paired: [Color] = [.screenBackground, .ink, .inkSecondary, .muted, .rule, .moss]
    for alias in paired {
      #expect(!resolvesIdenticallyAcrossSchemes(alias))
    }
  }
}
