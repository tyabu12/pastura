import Foundation
import Testing

@testable import Pastura

// CIEDE2000, and the tests that make it trustworthy.
//
// Split from `DesignTokensTests+NightAvatarInvariants.swift`: the metric is a
// general colour-difference helper, not a §2.5 invariant, and keeping the two
// together put that file past swiftlint's 400-line `file_length` cap once the
// reference-vector tests below were added.
//
// Every §2.5 character-identity assertion rests on this, so it is calibrated
// against published reference data rather than only against its own output.
//
// `@MainActor` on the members reading `PasturaColorValue` components: those are
// MainActor-isolated under `Views/`'s default isolation, and Swift's implicit
// exemption for reading immutable `Sendable` `let` storage applies only within
// the declaring module. `terms`, `meanHue`, `weightedDifference` and
// `degreesNormalized` take only `Double`s and plain structs of them, so they are
// correctly nonisolated. See `.claude/rules/swift-isolation.md` Pattern 5.
extension DesignTokensTests {

  // MARK: - The metric itself

  /// Smoke anchors over the **sRGB** entry point: 0 for a colour against itself,
  /// 100 for white against black.
  ///
  /// Deliberately not the whole calibration, and the reason is worth stating.
  /// White-vs-black has `C'₁ = C'₂ = 0` and `L̄' = 50`, so `ΔC'` and `ΔH'` both
  /// vanish, `S_L` is exactly 1, and the result collapses to `|ΔL'| = 100` —
  /// invariant to *any* error in `G`, `T`, `R_T`, `S_C`, `S_H`, `meanHue`, the
  /// hue-difference branches, or the `a`/`b` rows of the XYZ matrix. Swapping
  /// `greenRed` and `blueYellow` would pass both of these. The chromatic half
  /// is what the identity assertions actually depend on, so it is pinned
  /// separately below.
  @Test func perceptualDifferenceHasTheExpectedAchromaticAnchors() {
    let white = PasturaColorValue(hex: 0xFFFFFF)
    let black = PasturaColorValue(hex: 0x000000)
    #expect(abs(perceptualDifference(white, white)) < 0.001)
    #expect(abs(perceptualDifference(white, black) - 100.0) < 0.5)
  }

  /// The real calibration: published CIEDE2000 reference pairs, fed as `LabColor`
  /// so the check is of the difference formula alone and never touches sRGB.
  ///
  /// From Sharma, Wu & Dalal, "The CIEDE2000 Color-Difference Formula:
  /// Implementation Notes, Supplementary Test Data, and Mathematical
  /// Observations" (Color Research & Application, 2005). Each pair is chosen to
  /// stress a different term the achromatic anchors leave untouched — the hue
  /// term and `S_H`, the `R_T` rotation in the h̄' ≈ 275° region, the
  /// `G` chroma compensation at high chroma, the arctangent quadrant handling,
  /// and a mid-chroma green where `T` dominates. A transposed matrix row or a
  /// dropped weighting term fails at least one of them.
  @Test func perceptualDifferenceMatchesPublishedReferenceData() {
    let cases: [ReferencePair] = [
      ReferencePair(
        first: LabColor(lightness: 50, greenRed: 2.6772, blueYellow: -79.7751),
        second: LabColor(lightness: 50, greenRed: 0, blueYellow: -82.7485),
        expected: 2.0425),
      ReferencePair(
        first: LabColor(lightness: 22.7233, greenRed: 20.0904, blueYellow: -46.6940),
        second: LabColor(lightness: 23.0331, greenRed: 14.9730, blueYellow: -42.5619),
        expected: 2.0373),
      ReferencePair(
        first: LabColor(lightness: 36.4612, greenRed: 47.8580, blueYellow: 18.3852),
        second: LabColor(lightness: 36.2715, greenRed: 50.5065, blueYellow: 21.2231),
        expected: 1.4146),
      ReferencePair(
        first: LabColor(lightness: 50, greenRed: 2.5, blueYellow: 0),
        second: LabColor(lightness: 50, greenRed: 0, blueYellow: -2.5),
        expected: 4.3065),
      ReferencePair(
        first: LabColor(lightness: 60.2574, greenRed: -34.0099, blueYellow: 36.2677),
        second: LabColor(lightness: 60.4626, greenRed: -34.1751, blueYellow: 39.4387),
        expected: 1.2644)
    ]
    for pair in cases {
      #expect(abs(labDifference(pair.first, pair.second) - pair.expected) < 0.001)
    }
  }
}

/// One published reference pair. A tuple would trip swiftlint's `large_tuple`.
private struct ReferencePair {
  let first: LabColor
  let second: LabColor
  let expected: Double
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
  labDifference(labColor(of: lhs), labColor(of: rhs))
}

/// CIEDE2000 between two `LabColor`s, bypassing sRGB.
///
/// Separate entry point so `perceptualDifferenceMatchesPublishedReferenceData`
/// can feed the published Lab pairs directly: routing them through sRGB would
/// fold the colour-space conversion's own error into the comparison and stop it
/// being a check of the difference formula. Nonisolated — it reads no
/// `PasturaColorValue`.
func labDifference(_ first: LabColor, _ second: LabColor) -> Double {
  weightedDifference(terms(from: first, to: second))
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
