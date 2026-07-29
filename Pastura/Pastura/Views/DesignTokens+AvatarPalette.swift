import SwiftUI

// The §2.5 sheep-character palette — both halves, light and dark, in one file.
//
// Split out when ADR-028 gate 1's slice 4 landed. The axis is **a completed
// section moves out whole**, which is a third axis after slice 2's "the night
// data leaves the day file" and the value-vs-invariant one slice 3 declined:
// §2.5 was finished by slice 3, so unlike every other section it will not grow
// again, and taking both halves at once is what freed headroom in `DesignTokens.swift`
// (396 of swiftlint's 400-line `file_length` cap, with slice 4's own doc edits
// still to land) and in `DesignTokens+NightPalette.swift` (372, taking ten new
// night tokens) from a single move.
//
// **Keep the `DesignTokens` filename prefix.** `check_design_tokens_css.py` globs
// `Pastura/Pastura/Views/DesignTokens*.swift`, and this file now holds every
// §2.5 hex literal — rename it out of that glob and the `tokens.css` mirror gate
// goes blind with no signal.
//
// For §2.5 avatar colors the doc mirrors `demo-replay-reference.html`'s
// `sheepAvatar()` — but that prototype is LIGHT-ONLY, so the exception covers
// the light half alone; §2.9 is the origin of the §2.5 dark values. (Moved here
// from `DesignTokens.swift`'s header along with the tokens it describes.)
//
// Every `nightAvatar*` token below is the dark half of a `PasturaDynamicPalette`
// pair (`DesignTokens+DynamicPalette.swift`), reached through the repointed
// light `Color.*` alias. Those aliases have no production consumer: avatar
// painting goes through `SheepAvatarPalette`, which reads raw `PasturaPalette`
// so the `HighlightShareCard` export can pin one appearance (ADR-028 slice 3).

extension PasturaPalette {

  // MARK: §2.5 Avatar palette (sheep characters)
  //
  // Naming convention: shared parts use `avatarPart` (e.g. `avatarEar`);
  // per-character parts use `avatarPartCharacter` (e.g. `avatarBodyAlice`).

  /// Alice — body (wool / cream). Gentle first voice.
  static let avatarBodyAlice = PasturaColorValue(hex: 0xF2E3C8)
  /// Bob — body (wool / sage). Agreeable / calm.
  static let avatarBodyBob = PasturaColorValue(hex: 0xDDE4CC)
  /// Carol — body (wool / pink). Observer.
  static let avatarBodyCarol = PasturaColorValue(hex: 0xEAD6D1)
  /// Dave — body (wool / slate). Wolf / central figure.
  static let avatarBodyDave = PasturaColorValue(hex: 0xD9D7C9)

  /// Alice — face oval (darker cream accent over body).
  static let avatarFaceAlice = PasturaColorValue(hex: 0xC9A979)
  /// Bob — face oval (moss accent over body).
  static let avatarFaceBob = PasturaColorValue(hex: 0x8A9A6C)
  /// Carol — face oval (terracotta accent over body).
  static let avatarFaceCarol = PasturaColorValue(hex: 0xB8877C)
  /// Dave — face oval (deep slate accent over body).
  static let avatarFaceDave = PasturaColorValue(hex: 0x6B6858)

  /// Alice — horn stroke.
  static let avatarHornAlice = PasturaColorValue(hex: 0xB29364)
  /// Bob — horn stroke.
  static let avatarHornBob = PasturaColorValue(hex: 0x6F7F54)
  /// Carol — horn stroke.
  static let avatarHornCarol = PasturaColorValue(hex: 0x9C6E64)
  /// Dave — horn stroke.
  static let avatarHornDave = PasturaColorValue(hex: 0x4F4C3F)

  /// Shared avatar ear color.
  static let avatarEar = PasturaColorValue(hex: 0xE8D9BC)
  /// Inner ear tint.
  static let avatarEarInner = PasturaColorValue(hex: 0xD4C19E)
  /// Avatar nose.
  static let avatarNose = PasturaColorValue(hex: 0x3D4030)
  /// Avatar eye.
  static let avatarEye = PasturaColorValue(hex: 0x2D2E26)
  /// Translucent highlight (rgba(255,255,255,.6)).
  static let avatarHighlight = PasturaColorValue(hex: 0xFFFFFF, opacity: 0.6)

  // MARK: §2.9 Dark counterparts of the §2.5 character palette
  //
  // The "moonlit pasture" treatment, which is a **fourth** arm — ADR-028 named
  // this palette as the one item none of the first three fit, and measurement
  // agreed: arm 1's accent deltas blow a L=87% cream body out on a dark ground;
  // arm 2's role inversion erases the character identities, because those are
  // carried by HUE at near-equal lightness (the four light bodies sit within
  // 1.03-1.14 contrast of each other); and arm 3 places by contrast against a
  // known ground, which is not what a wool mass is for.
  //
  // What it is instead: the four bodies move down **as a family**, each keeping
  // its hue and its absolute chroma, and then every other part of a character
  // follows from THAT character's own light body-to-part contrast ratio. So the
  // sheep dims without being recoloured, and its interior structure — which is
  // what actually reads a sheep at 18-48pt, since in light the body separates
  // from the page by only 1.21-1.39 — is preserved rather than transformed.
  //
  // **Where the family sits, and why that number is a consequence rather than a
  // target.** The family SPANS a 7.0-8.0:1 window on `nightBackground` — Alice
  // at 7.99 sits essentially on the ceiling (`nightMoss` is 8.00) and Dave at
  // 7.02 on the floor, so the window has no slack left in either direction.
  // The window is what is designed: below ~7:1 Dave's interior collapses (his
  // eye-on-face is the palette's thinnest step and falls under 1.8), above
  // ~8:1 the wool overtakes `nightMoss` (8.00:1) and the decoration starts
  // out-shouting the brand accent. Stating it as "placed at 7.5:1 on the
  // ground" would be arm-3 reasoning on a token that has no legibility duty,
  // and the next slice would inherit it as precedent.
  //
  // **The floor is the mirror of slice 2's ceiling.** Slice 2 found that the
  // dark ground has a ceiling the light one does not. Here the same thing
  // happens at the bottom: light's near-white ground affords 20:1 of downward
  // headroom, so light can afford a horn 5.95x below its body, but the night
  // ground IS the floor. So the one relation that could not be preserved is
  // eye-on-face, which compresses (Dave 2.45 -> 1.93); every character lands at
  // 86% of what a pure-black eye could even reach.
  //
  // Design record and the rendered sign-off:
  // `docs/design/ds/colors-avatar-dark.html`.

  /// Alice's wool under dark mode — cream, the warmest and lightest of the four.
  static let nightAvatarBodyAlice = PasturaColorValue(hex: 0xBFB095)
  /// Bob's wool under dark mode — sage.
  static let nightAvatarBodyBob = PasturaColorValue(hex: 0xABB29A)
  /// Carol's wool under dark mode — pink.
  static let nightAvatarBodyCarol = PasturaColorValue(hex: 0xBAA6A0)
  /// Dave's wool under dark mode — slate, the least saturated of the four, which
  /// is his identity as much as his hue is.
  static let nightAvatarBodyDave = PasturaColorValue(hex: 0xA9A798)

  /// Alice's face under dark mode (1.75x below her body; light is 1.76x).
  static let nightAvatarFaceAlice = PasturaColorValue(hex: 0x9F7F4F)
  /// Bob's face under dark mode (2.32x below his body, as in light).
  ///
  /// Light's value is the same hex as `moss` (#8A9A6C), and that coincidence is
  /// deliberately **not** carried across. `nightMoss` (#A8B888) is *brighter*
  /// than Bob's dark body, so following it would put his face at 1.03:1 against
  /// his own wool — the face would not merely brighten, it would disappear. The
  /// accent brightens in dark because its job is legibility on the night
  /// ground; a face has the opposite job, so the two diverge.
  static let nightAvatarFaceBob = PasturaColorValue(hex: 0x637446)
  /// Carol's face under dark mode (2.22x below her body; light is 2.21x — the
  /// smallest interior drift of the eight at 0.10%, so the rounded digits differ
  /// while the relationship is the best-preserved of the set).
  static let nightAvatarFaceCarol = PasturaColorValue(hex: 0x936156)
  /// Dave's face under dark mode (3.86x below his body; light is 3.87x) — the
  /// strongest interior contrast of the four, which is the wolf's tell.
  static let nightAvatarFaceDave = PasturaColorValue(hex: 0x4A4737)

  /// Alice's horns under dark mode (2.32x below her body; light is 2.29x — the
  /// widest interior drift of the eight, at 1.32%).
  static let nightAvatarHornAlice = PasturaColorValue(hex: 0x8A6B3D)
  /// Bob's horns under dark mode (3.31x below his body; light is 3.32x).
  static let nightAvatarHornBob = PasturaColorValue(hex: 0x4D5C31)
  /// Carol's horns under dark mode (3.13x below her body; light is 3.11x).
  static let nightAvatarHornCarol = PasturaColorValue(hex: 0x794B41)
  /// Dave's horns under dark mode (6.02x below his body; light is 5.95x).
  ///
  /// This is the token the floor binds hardest: it sits at 1.17:1 against
  /// `nightBackground`, i.e. barely distinguishable from the night ground —
  /// which is fine, because horns are stroked ON the wool and never touch the
  /// background. Light's horn is at the opposite extreme for the same reason
  /// (8.25:1 *below* its pale ground); both are "as dark as this appearance
  /// affords".
  static let nightAvatarHornDave = PasturaColorValue(hex: 0x2C291C)

  /// Shared ear under dark mode.
  ///
  /// **No renderer draws this.** Neither `SheepAvatar`'s `Canvas` nor
  /// `sheepAvatar()` in `docs/design/demo-replay-reference.html` — the source of
  /// truth for §2.5's **light** values only —
  /// emits an ear — both draw body, face, eyes and horns only. Beware the decoy
  /// in that same prototype: a *different* function, `sheepSvg(bodyStroke:
  /// faceColor: earColor:)`, **does** draw ears — but it is the side-view
  /// assistant-mark builder, its ears take a hardcoded hex rather than this
  /// token, and the marks it builds (`MARKS.sheep_*`) are ones `MARK()` never
  /// returns. Two readers have now reached the wrong conclusion from it, in
  /// opposite directions. It is paired
  /// anyway because §2.5 is public palette API and a half-paired section is a
  /// state no count paragraph can describe; the value rides the body family, so
  /// it stays correct if a renderer ever grows ears. Swatch-reviewed only —
  /// there is no in-scene validation path for it and there cannot be one.
  static let nightAvatarEar = PasturaColorValue(hex: 0xB8A88B)
  /// Shared inner ear under dark mode. Drawn by no renderer — see
  /// `nightAvatarEar`.
  static let nightAvatarEarInner = PasturaColorValue(hex: 0xA79471)
  /// Shared nose under dark mode. Drawn by no renderer — see `nightAvatarEar`.
  ///
  /// Placed by holding its light contrast against the eye (1.29:1 -> 1.28:1)
  /// rather than against the faces, because light's nose is a softened eye and
  /// riding the face family instead drove it *below* the eye, inverting the
  /// linework's ordering. Light's value is the same hex as `mossInk`; that
  /// coincidence is **not** carried across, since `mossInk` stays unpaired
  /// until slice 4 and inheriting would make this a forward dependency on a
  /// value nobody has chosen yet.
  static let nightAvatarNose = PasturaColorValue(hex: 0x2A2D1D)
  /// Shared eye under dark mode — the darkest mark on the sheep, in both
  /// appearances.
  ///
  /// Light's value is the same hex as `ink` (#2D2E26). Inheriting that would
  /// make the eyes `nightInk` and therefore **white**, which is why the
  /// coincidence is cut. Holding #2D2E26 fixed in both appearances was the
  /// other candidate and is also wrong: `nightAvatarHornDave` is darker than
  /// it, so the wolf's horn would read as darker than his own pupil. So the eye
  /// is paired, and placed at the palette's own near-black floor — **HSL** L=7.5%,
  /// just under the HSL L=9.4% that light's darkest shipped token
  /// (`metaStrongL4`) uses. Note the unit: every other figure in this MARK is a
  /// WCAG contrast ratio.
  /// Pure black is refused for the reason `nightMetaStrongL4` refuses pure
  /// white: light ships a near-black, so the asymmetry would be the anomaly.
  static let nightAvatarEye = PasturaColorValue(hex: 0x16170F)

  /// Specular sheen over the face under dark mode — the one alpha token in
  /// §2.5.
  ///
  /// Alpha goes **down** (0.60 -> 0.40) where §2.7's washes went up by ~1.33x.
  /// Not an inconsistency: a wash is a tint that has to register against a dark
  /// surface, so it needs more alpha; this is a light reflection whose job is a
  /// fixed relative step above the face, and the face got darker while white
  /// stayed white — the same alpha would read as a *louder* step than in light.
  /// Opposite jobs, opposite directions.
  static let nightAvatarHighlight = PasturaColorValue(hex: 0xFFFFFF, opacity: 0.4)
}
