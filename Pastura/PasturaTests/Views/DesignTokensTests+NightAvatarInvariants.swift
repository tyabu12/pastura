import Foundation
import Testing

@testable import Pastura

// The properties the §2.5 dark values were DESIGNED to hold, as executable
// assertions (ADR-028 gate 1 slice 3).
//
// Every guard here comes in a pair: one test asserting the shipped palette
// satisfies the property, and one **negative control** asserting a
// deliberately-broken input violates it. A guard's success case proves nothing
// on its own — the palette could satisfy a predicate that is vacuously true —
// so each predicate is written as a pure function over supplied values and then
// fed a perturbation built to trip it. That keeps the control in the suite
// permanently rather than as a one-off manual probe.
//
// Split from `DesignTokensTests+NightAvatar.swift` (the value assertions) only
// for length: the CIEDE2000 implementation plus eight tests would put that file
// near swiftlint's 400-line `file_length` cap.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden.
extension DesignTokensTests {

  // MARK: - Interior structure is preserved, not transformed

  /// Each character keeps its own light body-to-face and body-to-horn contrast
  /// ratio. This is the core of the fourth arm: the family moves down, the
  /// interior relationships do not change.
  ///
  /// Tolerance is 3% *relative*, not absolute — at the dark end an 8-bit hex
  /// step moves a ratio by more than a hundredth. The binding case is **Alice's
  /// horn** at 1.32% (2.319 dark against light's 2.289); Dave's horn is second
  /// at 1.04% (6.02 against 5.95) and the other six are all under 0.5%. So the
  /// 3% bar is 2.3x the worst observed drift — headroom for quantization, not a
  /// figure fitted to let the shipped values through.
  @Test func nightAvatarInteriorRatiosMatchLight() {
    for character in AvatarCharacterTokens.all {
      #expect(interiorRatiosMatch(character, tolerance: 0.03))
    }
  }

  /// Negative control for `nightAvatarInteriorRatiosMatchLight`.
  ///
  /// Flattens the dark face onto the dark body — the exact failure the guard
  /// exists to catch, a face that stops separating from the wool — and confirms
  /// the predicate rejects it. Without this, a predicate that always returned
  /// `true` would look identical from the passing side.
  @Test func interiorRatioCheckRejectsAFaceFlattenedOntoTheBody() {
    let alice = AvatarCharacterTokens.alice
    let flattened = AvatarCharacterTokens(
      lightBody: alice.lightBody, lightFace: alice.lightFace, lightHorn: alice.lightHorn,
      darkBody: alice.darkBody, darkFace: alice.darkBody, darkHorn: alice.darkHorn)
    #expect(!interiorRatiosMatch(flattened, tolerance: 0.03))
  }

  // MARK: - The eye is the darkest mark, in both appearances

  /// The sheep's linework has an ordering: the eye is darker than the nose,
  /// which is darker than every horn and face. It holds in light and must keep
  /// holding in dark.
  @Test func nightAvatarEyeIsTheDarkestMark() {
    #expect(eyeIsDarkest(eye: PasturaPalette.avatarEye, inDark: false))
    #expect(eyeIsDarkest(eye: PasturaPalette.nightAvatarEye, inDark: true))
  }

  /// Negative control for `nightAvatarEyeIsTheDarkestMark`, and the recorded
  /// evidence for one of this slice's design decisions.
  ///
  /// Holding light's eye (#2D2E26) fixed in both appearances was the alternative
  /// to pairing it. This asserts why that was rejected: `nightAvatarHornDave` is
  /// darker than #2D2E26, so the wolf's horn would read as darker than his own
  /// pupil. The guard fires on exactly that substitution.
  @Test func eyeDarkestCheckRejectsHoldingTheLightEyeFixedInDark() {
    #expect(!eyeIsDarkest(eye: PasturaPalette.avatarEye, inDark: true))

    // The control alone does not isolate the cause the doc-comment records:
    // #2D2E26 is darker than TWO dark marks, and the second one
    // (`nightAvatarNose`) is an artefact of an incoherent counterfactual — the
    // nose was placed by holding 1.29:1 against the *paired* eye, so in a world
    // where the eye stayed light the nose would have been placed lighter too.
    // Dave's horn is the real reason, and it is a fact about shipped values
    // rather than about a hypothetical, so it is assertable directly.
    #expect(
      relativeLuminance(PasturaPalette.nightAvatarHornDave)
        < relativeLuminance(PasturaPalette.avatarEye))
  }

  // MARK: - Character identity survives the dimming

  /// Identity is carried by hue at near-equal lightness — the four light bodies
  /// sit within 1.03-1.14 contrast of each other — so "did the characters stay
  /// distinct" is a perceptual question, not a contrast one. Measured as
  /// CIEDE2000 between every pair of bodies.
  ///
  /// The bar is 95% of the light separation rather than 100%, and two distinct
  /// pairs are worth naming because it is easy to conflate them. The pair that
  /// **binds the floor** is Alice/Carol at 98.1%; the pair with the smallest
  /// *absolute* separation is Bob/Dave (ΔE 6.19 light, 6.10 dark) at 98.6%.
  /// **Four** of the six come out at or above light's; the two that dip are
  /// those. The guard exists to catch **convergence**, which would cost far
  /// more than a couple of percent.
  @Test func nightAvatarCharacterSeparationHoldsAgainstLight() {
    for (left, right) in AvatarCharacterTokens.pairs {
      #expect(separationHolds(left, right, floorFraction: 0.95))
    }
  }

  /// Negative control for `nightAvatarCharacterSeparationHoldsAgainstLight`.
  ///
  /// Collapses Bob's dark wool onto Dave's — two characters becoming one — and
  /// confirms the predicate rejects it.
  @Test func separationCheckRejectsTwoCharactersConverging() {
    let bob = AvatarCharacterTokens.bob
    let converged = AvatarCharacterTokens(
      lightBody: bob.lightBody, lightFace: bob.lightFace, lightHorn: bob.lightHorn,
      darkBody: AvatarCharacterTokens.dave.darkBody,
      darkFace: bob.darkFace, darkHorn: bob.darkHorn)
    #expect(!separationHolds(converged, AvatarCharacterTokens.dave, floorFraction: 0.95))
  }

  // MARK: - The body family sits inside its designed window

  /// The placement window is the thing §2.5's docs call **designed** — the
  /// per-character on-ground ratios are described everywhere as consequences of
  /// it — and until this it was the one claim in the slice that nothing
  /// executed. It is also the check that would have caught the wrong ground
  /// contrast that shipped in three doc sites and survived to code review.
  ///
  /// Floor 7.0:1 — below it Dave's interior collapses (his eye-on-face is the
  /// palette's thinnest step). Ceiling is `nightMoss`'s **own** ratio rather
  /// than a literal 8.0, so retuning the accent moves the ceiling with it
  /// instead of silently invalidating this test: decorative wool must not
  /// out-shout the brand accent.
  ///
  /// The window has no slack left — Alice sits at 7.99 against a ceiling of
  /// 8.00, Dave at 7.02 against a floor of 7.00 — so any future hex tweak in
  /// either direction reddens here.
  @Test func nightAvatarBodiesSitInsideTheDesignedWindow() {
    for tokens in AvatarCharacterTokens.all {
      #expect(bodySitsInWindow(tokens.darkBody))
    }
  }

  /// Negative control for `nightAvatarBodiesSitInsideTheDesignedWindow`.
  ///
  /// Feeds the predicate a body at `nightInk`'s luminance — wool as bright as
  /// body text, the "arm 1 blows out a cream body" failure ADR-028 names — and
  /// confirms it rejects. Pairs with the floor case below so neither bound is
  /// vacuous.
  @Test func windowCheckRejectsBodiesOutsideEitherBound() {
    #expect(!bodySitsInWindow(PasturaPalette.nightInk))
    #expect(!bodySitsInWindow(PasturaPalette.nightMuted))
  }

  // MARK: - The sheen keeps its step over the face

  /// The highlight is a specular mark whose job is a fixed relative step above
  /// the face. The faces darkened while white stayed white, so holding the step
  /// meant lowering alpha (0.60 -> 0.40) — the opposite of what §2.7's washes
  /// did, because a wash is a tint that must register on a dark surface.
  @Test func nightAvatarSheenKeepsItsStepOverTheFace() {
    #expect(sheenStepMatchesLight(darkAlpha: PasturaPalette.nightAvatarHighlight.opacity))
  }

  /// Negative control for `nightAvatarSheenKeepsItsStepOverTheFace`.
  ///
  /// Carrying light's 0.60 across unchanged is the mistake the alpha decision
  /// avoids; at that alpha the sheen reads as a louder step in dark than in
  /// light. Confirms the predicate rejects it.
  @Test func sheenStepCheckRejectsCarryingTheLightAlphaAcross() {
    #expect(!sheenStepMatchesLight(darkAlpha: PasturaPalette.avatarHighlight.opacity))
  }
}

// MARK: - Helpers
//
// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files".
// `@MainActor` on every member that reads a `PasturaColorValue`'s components —
// not only the ones reading `PasturaPalette` statics. `PasturaColorValue`'s
// stored properties are MainActor-isolated under `Views/`'s default isolation,
// and Swift's implicit exemption for reading immutable `Sendable` `let` storage
// applies only *within* the declaring module, so a `@testable import`-ed read
// from a nonisolated file-scope function does not compile. Verified by
// omission: the first draft left the colour-maths functions unannotated and the
// build failed with "main actor-isolated property 'red' can not be referenced
// from a nonisolated context". `terms`, `meanHue`, `weightedDifference` and
// `degreesNormalized` take only `Double`s and plain structs of them, so they
// are correctly nonisolated. `relativeLuminance`,
// `contrastRatio` and `composite` are NOT redeclared here — they already
// exist in `DesignTokensTests+NightPalette.swift` and were widened from
// `private` to internal so this file can reuse them. Same reasoning as
// `sRGBComponentsMatch` in `DesignTokensTests+DarkMode.swift`
// (`.claude/rules/swift-isolation.md` Pattern 5).

/// One character's six §2.5 tokens, light and dark, so the invariants can be
/// stated per character and also fed deliberately-broken variants.
@MainActor
struct AvatarCharacterTokens {
  let lightBody: PasturaColorValue
  let lightFace: PasturaColorValue
  let lightHorn: PasturaColorValue
  let darkBody: PasturaColorValue
  let darkFace: PasturaColorValue
  let darkHorn: PasturaColorValue

  static let alice = AvatarCharacterTokens(
    lightBody: PasturaPalette.avatarBodyAlice, lightFace: PasturaPalette.avatarFaceAlice,
    lightHorn: PasturaPalette.avatarHornAlice, darkBody: PasturaPalette.nightAvatarBodyAlice,
    darkFace: PasturaPalette.nightAvatarFaceAlice, darkHorn: PasturaPalette.nightAvatarHornAlice)
  static let bob = AvatarCharacterTokens(
    lightBody: PasturaPalette.avatarBodyBob, lightFace: PasturaPalette.avatarFaceBob,
    lightHorn: PasturaPalette.avatarHornBob, darkBody: PasturaPalette.nightAvatarBodyBob,
    darkFace: PasturaPalette.nightAvatarFaceBob, darkHorn: PasturaPalette.nightAvatarHornBob)
  static let carol = AvatarCharacterTokens(
    lightBody: PasturaPalette.avatarBodyCarol, lightFace: PasturaPalette.avatarFaceCarol,
    lightHorn: PasturaPalette.avatarHornCarol, darkBody: PasturaPalette.nightAvatarBodyCarol,
    darkFace: PasturaPalette.nightAvatarFaceCarol, darkHorn: PasturaPalette.nightAvatarHornCarol)
  static let dave = AvatarCharacterTokens(
    lightBody: PasturaPalette.avatarBodyDave, lightFace: PasturaPalette.avatarFaceDave,
    lightHorn: PasturaPalette.avatarHornDave, darkBody: PasturaPalette.nightAvatarBodyDave,
    darkFace: PasturaPalette.nightAvatarFaceDave, darkHorn: PasturaPalette.nightAvatarHornDave)

  static let all = [alice, bob, carol, dave]

  /// The six unordered character pairs.
  static let pairs: [(AvatarCharacterTokens, AvatarCharacterTokens)] = [
    (alice, bob), (alice, carol), (alice, dave), (bob, carol), (bob, dave), (carol, dave)
  ]
}

// MARK: Predicates

/// Both interior ratios within `tolerance` (relative) of the light originals.
@MainActor
func interiorRatiosMatch(_ tokens: AvatarCharacterTokens, tolerance: Double) -> Bool {
  let facePairs = (
    light: contrastRatio(tokens.lightBody, tokens.lightFace),
    dark: contrastRatio(tokens.darkBody, tokens.darkFace)
  )
  let hornPairs = (
    light: contrastRatio(tokens.lightBody, tokens.lightHorn),
    dark: contrastRatio(tokens.darkBody, tokens.darkHorn)
  )
  return abs(facePairs.dark / facePairs.light - 1) < tolerance
    && abs(hornPairs.dark / hornPairs.light - 1) < tolerance
}

/// `eye` is strictly darker than the nose and than every face and horn in the
/// given appearance.
@MainActor
func eyeIsDarkest(eye: PasturaColorValue, inDark: Bool) -> Bool {
  var marks = [inDark ? PasturaPalette.nightAvatarNose : PasturaPalette.avatarNose]
  for tokens in AvatarCharacterTokens.all {
    marks.append(inDark ? tokens.darkFace : tokens.lightFace)
    marks.append(inDark ? tokens.darkHorn : tokens.lightHorn)
  }
  let eyeLuminance = relativeLuminance(eye)
  return marks.allSatisfy { eyeLuminance < relativeLuminance($0) }
}

/// The dark bodies stay at least `floorFraction` of their light perceptual
/// separation apart.
@MainActor
func separationHolds(
  _ left: AvatarCharacterTokens, _ right: AvatarCharacterTokens, floorFraction: Double
) -> Bool {
  let light = perceptualDifference(left.lightBody, right.lightBody)
  let dark = perceptualDifference(left.darkBody, right.darkBody)
  return dark >= light * floorFraction
}

/// Whether a dark wool value sits inside the designed placement window on
/// `nightBackground`: at or above 7.0:1, and at or below `nightMoss`'s own
/// ratio against the same ground.
@MainActor
func bodySitsInWindow(_ body: PasturaColorValue) -> Bool {
  let onGround = contrastRatio(body, PasturaPalette.nightBackground)
  let ceiling = contrastRatio(PasturaPalette.nightMoss, PasturaPalette.nightBackground)
  return onGround >= 7.0 && onGround <= ceiling
}

/// White at `darkAlpha` over each dark face lands within 12% of the mean step
/// that white at 0.60 makes over the light faces.
///
/// The tolerance is deliberately loose relative to the shipped value, which
/// deviates by only 1.0% (light mean 2.238, dark-at-0.40 mean 2.256). It is
/// sized to the *decision* rather than the value: the passing band is roughly
/// alpha 0.32-0.47, so this asserts "the alpha was re-derived downward for the
/// dark faces", not "0.40 is the unique right answer". Light's own 0.60 lands
/// at 43.5% and is rejected. Tightening it toward 5% would make it a
/// change-detector on a value nothing else pins — which is a different guard,
/// and would need the doc-comment to say so.
@MainActor
func sheenStepMatchesLight(darkAlpha: Double) -> Bool {
  func meanStep(faces: [PasturaColorValue], alpha: Double) -> Double {
    let white = PasturaColorValue(hex: 0xFFFFFF)
    let steps = faces.map { contrastRatio(composite(white, over: $0, alpha: alpha), $0) }
    return steps.reduce(0, +) / Double(steps.count)
  }
  let light = meanStep(faces: AvatarCharacterTokens.all.map(\.lightFace), alpha: 0.6)
  let dark = meanStep(faces: AvatarCharacterTokens.all.map(\.darkFace), alpha: darkAlpha)
  return abs(dark / light - 1) < 0.12
}
