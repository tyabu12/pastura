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
  /// step moves a ratio by more than a hundredth (Dave's horn ratio lands at
  /// 6.00 against light's 5.95, which is quantization, not drift).
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
  }

  // MARK: - Character identity survives the dimming

  /// Identity is carried by hue at near-equal lightness — the four light bodies
  /// sit within 1.03-1.14 contrast of each other — so "did the characters stay
  /// distinct" is a perceptual question, not a contrast one. Measured as
  /// CIEDE2000 between every pair of bodies.
  ///
  /// The bar is 95% of the light separation rather than 100%: the closest pair
  /// in both appearances (Bob/Dave, the sage and the slate) lands at 98.1%, and
  /// the guard exists to catch **convergence**, which would cost far more than
  /// a few percent. Five of the six pairs come out at or above light's.
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

  // MARK: - The metric itself

  /// `perceptualDifference` is ~55 lines of unexercised colour maths, and every
  /// identity assertion above rests on it. These two anchors are the cheapest
  /// way to know it is not returning a constant: CIEDE2000 is 0 for a colour
  /// against itself and 100 for white against black.
  @Test func perceptualDifferenceMetricIsCalibrated() {
    let white = PasturaColorValue(hex: 0xFFFFFF)
    let black = PasturaColorValue(hex: 0x000000)
    #expect(abs(perceptualDifference(white, white)) < 0.001)
    #expect(abs(perceptualDifference(white, black) - 100.0) < 0.5)
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

/// White at `darkAlpha` over each dark face lands within 12% of the mean step
/// that white at 0.60 makes over the light faces.
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

// MARK: Perceptual difference (CIEDE2000)
//
// Spelled out rather than using the formula's single-letter symbols: swiftlint's
// `identifier_name` floor is 3 characters, and the expansion is the honest
// trade — the published algorithm's `a1` / `C1'` / `Sl` are unreadable to
// anyone not holding the paper anyway. Split across two functions and two small
// structs so no body crosses `function_body_length` and no signature crosses
// `function_parameter_count` / `large_tuple`.

/// CIELAB coordinates under D65.
struct LabColor {
  let lightness: Double
  let greenRed: Double
  let blueYellow: Double
}

/// The intermediate quantities CIEDE2000's weighting half consumes.
private struct DifferenceTerms {
  let deltaLightness: Double
  let deltaChroma: Double
  let deltaHue: Double
  let meanLightness: Double
  let meanChroma: Double
  let meanHueDegrees: Double
}

@MainActor
func labColor(of value: PasturaColorValue) -> LabColor {
  func channel(_ component: Double) -> Double {
    component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
  }
  let red = channel(value.red)
  let green = channel(value.green)
  let blue = channel(value.blue)
  let tristimulusX = (0.4124564 * red + 0.3575761 * green + 0.1804375 * blue) / 0.95047
  let tristimulusY = 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue
  let tristimulusZ = (0.0193339 * red + 0.1191920 * green + 0.9503041 * blue) / 1.08883
  func pivot(_ component: Double) -> Double {
    component > 216.0 / 24389.0
      ? pow(component, 1.0 / 3.0) : (841.0 / 108.0) * component + 4.0 / 29.0
  }
  let pivotX = pivot(tristimulusX)
  let pivotY = pivot(tristimulusY)
  let pivotZ = pivot(tristimulusZ)
  return LabColor(
    lightness: 116 * pivotY - 16,
    greenRed: 500 * (pivotX - pivotY),
    blueYellow: 200 * (pivotY - pivotZ))
}

/// CIEDE2000 perceptual difference.
///
/// Identity here is carried by hue at near-equal lightness, so a contrast or
/// raw-channel metric would report the four characters as nearly identical and
/// prove nothing. Calibrated by `perceptualDifferenceMetricIsCalibrated`.
@MainActor
func perceptualDifference(_ lhs: PasturaColorValue, _ rhs: PasturaColorValue) -> Double {
  weightedDifference(terms(from: labColor(of: lhs), to: labColor(of: rhs)))
}

private func terms(from first: LabColor, to second: LabColor) -> DifferenceTerms {
  let meanRawChroma =
    (hypot(first.greenRed, first.blueYellow) + hypot(second.greenRed, second.blueYellow)) / 2
  let raised = pow(meanRawChroma, 7)
  let compensation = 0.5 * (1 - (raised / (raised + pow(25.0, 7))).squareRoot())
  let firstGreenRed = (1 + compensation) * first.greenRed
  let secondGreenRed = (1 + compensation) * second.greenRed
  let firstChroma = hypot(firstGreenRed, first.blueYellow)
  let secondChroma = hypot(secondGreenRed, second.blueYellow)
  let firstHue = firstChroma == 0 ? 0 : atan2(first.blueYellow, firstGreenRed).degreesNormalized
  let secondHue =
    secondChroma == 0 ? 0 : atan2(second.blueYellow, secondGreenRed).degreesNormalized
  var hueDelta = 0.0
  if firstChroma * secondChroma != 0 {
    let raw = secondHue - firstHue
    hueDelta = abs(raw) <= 180 ? raw : (raw > 0 ? raw - 360 : raw + 360)
  }
  return DifferenceTerms(
    deltaLightness: second.lightness - first.lightness,
    deltaChroma: secondChroma - firstChroma,
    deltaHue: 2 * (firstChroma * secondChroma).squareRoot() * sin((hueDelta / 2) * .pi / 180),
    meanLightness: (first.lightness + second.lightness) / 2,
    meanChroma: (firstChroma + secondChroma) / 2,
    meanHueDegrees: meanHue(firstHue, secondHue, firstChroma * secondChroma != 0))
}

private func meanHue(_ first: Double, _ second: Double, _ bothChromatic: Bool) -> Double {
  guard bothChromatic else { return first + second }
  if abs(first - second) <= 180 { return (first + second) / 2 }
  return first + second < 360 ? (first + second + 360) / 2 : (first + second - 360) / 2
}

private func weightedDifference(_ terms: DifferenceTerms) -> Double {
  func cosDegrees(_ degrees: Double) -> Double { cos(degrees * .pi / 180) }
  let hueWeight =
    1 - 0.17 * cosDegrees(terms.meanHueDegrees - 30) + 0.24 * cosDegrees(2 * terms.meanHueDegrees)
    + 0.32 * cosDegrees(3 * terms.meanHueDegrees + 6)
    - 0.20 * cosDegrees(4 * terms.meanHueDegrees - 63)
  let raised = pow(terms.meanChroma, 7)
  let lightnessOffset = pow(terms.meanLightness - 50, 2)
  let scaleLightness = 1 + (0.015 * lightnessOffset) / (20 + lightnessOffset).squareRoot()
  let scaleChroma = 1 + 0.045 * terms.meanChroma
  let scaleHue = 1 + 0.015 * terms.meanChroma * hueWeight
  let rotation =
    -sin(2 * (30 * exp(-pow((terms.meanHueDegrees - 275) / 25, 2))) * .pi / 180)
    * 2 * (raised / (raised + pow(25.0, 7))).squareRoot()
  let lightnessTerm = terms.deltaLightness / scaleLightness
  let chromaTerm = terms.deltaChroma / scaleChroma
  let hueTerm = terms.deltaHue / scaleHue
  return
    (pow(lightnessTerm, 2) + pow(chromaTerm, 2) + pow(hueTerm, 2)
    + rotation * chromaTerm * hueTerm).squareRoot()
}

extension Double {
  /// Radians to degrees, wrapped into `0..<360`.
  fileprivate var degreesNormalized: Double {
    let degrees = self * 180 / .pi
    return degrees < 0 ? degrees + 360 : degrees
  }
}
