import SwiftUI
import Testing

@testable import Pastura

/// Pins ``SheepAvatarPalette`` to **raw** `PasturaPalette` values (ADR-028 gate
/// 1 slice 3).
///
/// Why this suite exists: pairing the §2.5 tokens made every `Color.avatar*`
/// alias trait-resolving, and ``SheepAvatar`` renders inside
/// ``HighlightShareCard``'s `ImageRenderer` export. If an alias creeps into this
/// palette, the sheep's colours start tracking the render environment instead of
/// the fixed values pinned below — and nothing else would notice, because
/// `ImageRenderer` output is asserted nowhere and ADR-009 rules out the snapshot
/// test that would catch it. Sibling of ``HighlightShareCardPaletteTests``, which
/// guards the same contract one level up.
///
/// **What that costs, measured in #1337:** not a dark export rendering light.
/// The render environment is the `colorScheme` the export injects, so an alias
/// would still resolve to the requested appearance — but `light` and `dark` would
/// resolve to the same thing, making the caller's choice inert, and the export
/// would depend on a platform behaviour Apple owns. See ADR-028
/// § Amendment 2026-08-06 (#1337).
///
/// What this suite does **not** cover: that ``HighlightShareCard`` actually
/// passes its `colorScheme` down, and that ``SheepAvatar`` reads
/// `@Environment(\.colorScheme)` when it does not. Both are View-tree wiring,
/// which ADR-009 leaves to code review and device QA.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SheepAvatarPaletteTests {

  private static let characters: [SheepAvatar.Character] = [.alice, .bob, .carol, .dave]

  private static let lightExpectations: [CharacterExpectation] = [
    CharacterExpectation(
      character: .alice, body: PasturaPalette.avatarBodyAlice,
      face: PasturaPalette.avatarFaceAlice, horn: PasturaPalette.avatarHornAlice),
    CharacterExpectation(
      character: .bob, body: PasturaPalette.avatarBodyBob,
      face: PasturaPalette.avatarFaceBob, horn: PasturaPalette.avatarHornBob),
    CharacterExpectation(
      character: .carol, body: PasturaPalette.avatarBodyCarol,
      face: PasturaPalette.avatarFaceCarol, horn: PasturaPalette.avatarHornCarol),
    CharacterExpectation(
      character: .dave, body: PasturaPalette.avatarBodyDave,
      face: PasturaPalette.avatarFaceDave, horn: PasturaPalette.avatarHornDave)
  ]

  private static let darkExpectations: [CharacterExpectation] = [
    CharacterExpectation(
      character: .alice, body: PasturaPalette.nightAvatarBodyAlice,
      face: PasturaPalette.nightAvatarFaceAlice, horn: PasturaPalette.nightAvatarHornAlice),
    CharacterExpectation(
      character: .bob, body: PasturaPalette.nightAvatarBodyBob,
      face: PasturaPalette.nightAvatarFaceBob, horn: PasturaPalette.nightAvatarHornBob),
    CharacterExpectation(
      character: .carol, body: PasturaPalette.nightAvatarBodyCarol,
      face: PasturaPalette.nightAvatarFaceCarol, horn: PasturaPalette.nightAvatarHornCarol),
    CharacterExpectation(
      character: .dave, body: PasturaPalette.nightAvatarBodyDave,
      face: PasturaPalette.nightAvatarFaceDave, horn: PasturaPalette.nightAvatarHornDave)
  ]

  private func palette(
    _ character: SheepAvatar.Character, _ scheme: ColorScheme
  ) -> SheepAvatarPalette {
    SheepAvatarPalette.resolved(for: character, colorScheme: scheme)
  }

  @Test func lightPaletteReadsRawLightTokens() {
    for expected in Self.lightExpectations {
      let resolved = palette(expected.character, .light)
      #expect(resolved.body == expected.body.color)
      #expect(resolved.face == expected.face.color)
      #expect(resolved.horn == expected.horn.color)
      #expect(resolved.eye == PasturaPalette.avatarEye.color)
      #expect(resolved.highlight == PasturaPalette.avatarHighlight.color)
    }
  }

  @Test func darkPaletteReadsRawNightTokens() {
    for expected in Self.darkExpectations {
      let resolved = palette(expected.character, .dark)
      #expect(resolved.body == expected.body.color)
      #expect(resolved.face == expected.face.color)
      #expect(resolved.horn == expected.horn.color)
      #expect(resolved.eye == PasturaPalette.nightAvatarEye.color)
      #expect(resolved.highlight == PasturaPalette.nightAvatarHighlight.color)
    }
  }

  /// The fixed-appearance contract itself: every slot of both appearances
  /// resolves identically whichever scheme it is asked about. Alias creep
  /// reddens here, because a paired alias does not.
  ///
  /// Slots come from `Mirror`, not a hand list — see the same note on
  /// ``HighlightShareCardPaletteTests/rawPaletteValuesAreAppearanceInvariant``.
  /// `expectedSlotCount` is five because `avatarEar`, `avatarEarInner` and
  /// `avatarNose` are tokens no renderer draws, which this palette's own doc
  /// comment records; adding one here must be a deliberate edit, not a silent
  /// widening.
  @Test func everySlotIsAppearanceInvariant() {
    let expectedSlotCount = 5
    for character in Self.characters {
      for scheme in [ColorScheme.light, .dark] {
        let reflected = reflectedColorSlots(of: palette(character, scheme))
        #expect(reflected.childCount == expectedSlotCount)
        #expect(reflected.colors.count == reflected.childCount)
        for slot in reflected.colors {
          #expect(resolvesIdenticallyAcrossSchemes(slot))
        }
      }
    }
  }

  /// Positive control for `everySlotIsAppearanceInvariant`.
  ///
  /// That test asserts a *negative* — "these do not vary" — which a broken
  /// comparison would also satisfy. This feeds the same check the aliases the
  /// palette replaced, which are trait-resolving since slice 3, and requires it
  /// to report them as varying. If this ever passes, the invariance assertions
  /// above are measuring nothing.
  @Test func theAliasesThisPaletteReplacedDoVaryAcrossSchemes() {
    let paired: [Color] = [
      .avatarBodyAlice, .avatarFaceBob, .avatarHornDave, .avatarEye, .avatarHighlight
    ]
    for alias in paired {
      #expect(!resolvesIdenticallyAcrossSchemes(alias))
    }
  }

  /// A token-value collapse the two mapping tests cannot see: if a future
  /// retune gave a night token its light hex, both would still pass while the
  /// avatar stopped changing between appearances.
  @Test func theTwoAppearancesAreNotIdentical() {
    for character in Self.characters {
      #expect(palette(character, .light).body != palette(character, .dark).body)
      #expect(palette(character, .light).face != palette(character, .dark).face)
      #expect(palette(character, .light).horn != palette(character, .dark).horn)
    }
    #expect(palette(.alice, .light).eye != palette(.alice, .dark).eye)
    #expect(palette(.alice, .light).highlight != palette(.alice, .dark).highlight)
  }
}

// MARK: - Helpers

/// One character's three per-character tokens. A tuple would trip swiftlint's
/// `large_tuple` (max 2 members).
@MainActor
private struct CharacterExpectation {
  let character: SheepAvatar.Character
  let body: PasturaColorValue
  let face: PasturaColorValue
  let horn: PasturaColorValue
}
