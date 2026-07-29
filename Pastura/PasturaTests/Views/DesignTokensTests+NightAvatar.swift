import Foundation
import Testing

@testable import Pastura

// sRGB component assertions for the §2.5 character-palette dark counterparts
// added by ADR-028 gate 1's slice 3 — the 17 sheep-avatar tokens.
//
// **The split axis here is per-section, not the one ADR-028's slice-2 Amendment
// prescribed** ("value assertions stay, invariant tests leave"). §2.5 takes a
// whole file — values *and* invariants — because that costs zero churn on the
// existing files and leaves every one of them further from swiftlint's 400-line
// `file_length` cap than the prescribed axis would: `+NightPalette` stays at its
// current length instead of being gutted and refilled, and this file lands
// around 240. The prescribed axis would have put the shared invariant file near
// 355, which slice 4 would immediately split again. ADR-028's Amendment records
// that this supersedes the prescribed axis for slices 3-4.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`, and reaches its `approxEqual`
// helper, which is internal-not-private for exactly this reason.
//
// These assert the VALUES. That the aliases are actually *wired* to them is a
// separate concern, covered in `DesignTokensTests+DarkModeWiring.swift`; the
// properties the values were designed to hold are asserted in
// `DesignTokensTests+NightAvatarInvariants.swift`.
extension DesignTokensTests {

  // MARK: - §2.9 dark counterparts of the §2.5 character palette

  /// The twelve per-character tokens.
  ///
  /// Character identity is carried by **hue**, not lightness: the four light
  /// bodies sit at L 82-87% and are only 1.03-1.14 apart in contrast, so the
  /// dark set holds each character's hue and absolute chroma and moves the
  /// family down as a block. See the invariants file for the assertions that
  /// pin that.
  @Test func nightAvatarCharacterPartsMatchSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightAvatarBodyAlice, 0xBFB095),
      (PasturaPalette.nightAvatarBodyBob, 0xABB29A),
      (PasturaPalette.nightAvatarBodyCarol, 0xBAA6A0),
      (PasturaPalette.nightAvatarBodyDave, 0xA9A798),
      (PasturaPalette.nightAvatarFaceAlice, 0x9F7F4F),
      (PasturaPalette.nightAvatarFaceBob, 0x637446),
      (PasturaPalette.nightAvatarFaceCarol, 0x936156),
      (PasturaPalette.nightAvatarFaceDave, 0x4A4737),
      (PasturaPalette.nightAvatarHornAlice, 0x8A6B3D),
      (PasturaPalette.nightAvatarHornBob, 0x4D5C31),
      (PasturaPalette.nightAvatarHornCarol, 0x794B41),
      (PasturaPalette.nightAvatarHornDave, 0x2C291C)
    ]

    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  /// The four shared opaque parts.
  ///
  /// Three of them — `nightAvatarEar`, `nightAvatarEarInner`, `nightAvatarNose`
  /// — are drawn by **no renderer**; see their declarations in
  /// `DesignTokens+NightPalette.swift` for why they are paired anyway.
  @Test func nightAvatarSharedPartsMatchSpec() {
    let cases: [(token: PasturaColorValue, hex: UInt32)] = [
      (PasturaPalette.nightAvatarEar, 0xB8A88B),
      (PasturaPalette.nightAvatarEarInner, 0xA79471),
      (PasturaPalette.nightAvatarNose, 0x2A2D1D),
      (PasturaPalette.nightAvatarEye, 0x16170F)
    ]

    for (token, hex) in cases {
      #expect(approxEqual(token.red, Double((hex >> 16) & 0xFF) / 255.0))
      #expect(approxEqual(token.green, Double((hex >> 8) & 0xFF) / 255.0))
      #expect(approxEqual(token.blue, Double(hex & 0xFF) / 255.0))
      #expect(approxEqual(token.opacity, 1.0))
    }
  }

  /// The one alpha token in §2.5 — a white specular mark over the face.
  ///
  /// Its alpha goes **down** (0.60 -> 0.40) where §2.7's washes went up. The
  /// washes are a tint that has to register on a dark surface; this is a light
  /// reflection whose job is a fixed relative step over the face, and the face
  /// got darker while white stayed white, so the same alpha would read as a
  /// *louder* step. Opposite jobs, opposite directions. The step itself is
  /// asserted in the invariants file.
  @Test func nightAvatarHighlightMatchesSpec() {
    let token = PasturaPalette.nightAvatarHighlight
    #expect(approxEqual(token.red, 1.0))
    #expect(approxEqual(token.green, 1.0))
    #expect(approxEqual(token.blue, 1.0))
    #expect(approxEqual(token.opacity, 0.4))
  }

  // MARK: - The three light-side hex coincidences this slice deliberately CUT

  /// Slice 2 carried two hex coincidences faithfully across into dark. Slice 3
  /// cuts all three of its own, so this pins the *cuts* — each would otherwise
  /// look like a drift a future reader should "fix".
  ///
  /// - `avatarEye == ink` in light: inheriting it would make the eyes
  ///   `nightInk` #E8E5D8, i.e. **white**. The eye is a facial feature, not body
  ///   text. Holding it fixed instead was also rejected: Dave's dark horn is
  ///   darker than #2D2E26, so the eye would stop being the darkest mark (that
  ///   ordering is asserted in the invariants file).
  /// - `avatarFaceBob == moss` in light: `nightMoss` is *brighter* than Bob's
  ///   dark body, so his face would read at 1.03:1 against his own wool — it
  ///   would not merely brighten, it would vanish.
  /// - `avatarNose == mossInk` in light: `mossInk` is unpaired until slice 4, so
  ///   inheriting would create a forward dependency on a value nobody has
  ///   chosen yet.
  @Test func nightAvatarCutsTheThreeLightHexCoincidences() {
    #expect(PasturaPalette.avatarEye.red == PasturaPalette.ink.red)
    #expect(!approxEqual(PasturaPalette.nightAvatarEye.red, PasturaPalette.nightInk.red))

    #expect(PasturaPalette.avatarFaceBob.red == PasturaPalette.moss.red)
    #expect(!approxEqual(PasturaPalette.nightAvatarFaceBob.red, PasturaPalette.nightMoss.red))

    #expect(PasturaPalette.avatarNose.red == PasturaPalette.mossInk.red)
  }
}
