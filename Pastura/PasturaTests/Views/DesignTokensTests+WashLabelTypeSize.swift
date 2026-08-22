import SwiftUI
import Testing
import UIKit

@testable import Pastura

// The WCAG large-text admission criterion the contrast fixtures apply,
// made executable (#1468).
//
// `DesignTokensTests+MossOnWash.swift`, `+MossInkAsWashLabel.swift`,
// `+InkOnWash.swift`, `+MossSoftGround.swift`, and the #1427 label rows in
// `+MutedTranscript.swift` each pin a 4.5:1 bar, and each is only the right bar
// because every label in its fixture is WCAG **normal** text. Until #1468 that
// was a prose claim over row types storing no font, so no arm observed it and a
// large-text row would have been admitted silently (#1466).
//
// This file owns the criterion and the negative controls for it; the fixtures
// own their rows. That split is deliberate: the controls exercise
// ``WashLabelWeight`` and each row type's `isNormalText`, which is what lives
// here, and it keeps the controls off the two fixture files closest to
// swiftlint's 400-line `file_length` error under `--strict`.
//
// Sibling-file extension of `DesignTokensTests` per `.claude/rules/testing.md`
// § "Splitting a Suite Across Files" — a fresh `@Suite` would run in parallel
// with the parent and is explicitly forbidden. Inherits the parent's
// `@MainActor` and `.timeLimit(.minutes(1))`.
extension DesignTokensTests {

  /// The boundary table both negative controls run. Written as expectations
  /// rather than derived from ``WashLabelWeight``, so a mapping that moved has
  /// something independent to disagree with.
  ///
  /// Each half is pinned from **both** sides, and `.semibold` needs three rows
  /// rather than two: `14 / .semibold` admitted is what separates it from
  /// `.bold`, while `18` rejected and `17.9` admitted are what say the half it
  /// takes is ≥18 rather than merely >14. With only the first, a threshold
  /// typed as 20 would pass every arm in the repo.
  ///
  /// **This table is the sole arbiter for both controls, so editing a row to
  /// green a red disarms them together** — the ordinary red-test reflex rather
  /// than sabotage, and no shipped row would redden alongside to warn you.
  /// ``everyWeightHalfIsPinnedFromBothSidesInTheTable`` is what makes a *lost*
  /// pin visible; a row merely *moved* (18 → 19) still passes it, and the count
  /// pin below survives any same-cardinality swap.
  static let washLabelBoundaryCases: [WashLabelBoundaryCase] = [
    WashLabelBoundaryCase(14, .bold, isNormalText: false),
    WashLabelBoundaryCase(13.9, .bold, isNormalText: true),
    WashLabelBoundaryCase(14, .semibold, isNormalText: true),
    WashLabelBoundaryCase(18, .semibold, isNormalText: false),
    WashLabelBoundaryCase(17.9, .semibold, isNormalText: true),
    WashLabelBoundaryCase(18, .regular, isNormalText: false),
    WashLabelBoundaryCase(17.9, .regular, isNormalText: true),
    WashLabelBoundaryCase(18, .medium, isNormalText: false),
    WashLabelBoundaryCase(17.9, .medium, isNormalText: true)
  ]

  /// The two semantic sizes are the only figures in any wash fixture with no
  /// token to reference, so they are measured rather than asserted in prose.
  ///
  /// `compatibleWith:` pins the content-size category explicitly: without it
  /// `preferredFont` reads the runner's ambient setting, and the arm would
  /// measure whatever the simulator happened to be configured for rather than
  /// the default this fixture's rows are recorded at.
  @Test func semanticLabelSizesMatchUIKitAtTheDefaultContentSize() {
    let large = UITraitCollection(preferredContentSizeCategory: .large)
    // SwiftUI's `.caption` is UIKit's `.caption1`.
    let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: large)
    let caption2 = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: large)
    #expect(Double(caption.pointSize) == WashLabelSemanticSize.caption)
    #expect(Double(caption2.pointSize) == WashLabelSemanticSize.caption2)
  }

  /// Coverage over the boundary table, which its own count pin cannot give:
  /// `count == 9` survives a same-cardinality swap and says nothing about a
  /// **fifth** ``WashLabelWeight`` case, which would ship with zero control
  /// rows while both negative controls stayed green.
  ///
  /// Deliberately structural, not value-derived: it asks that each case be
  /// pinned on both sides of its threshold without saying where that threshold
  /// is, so the table stays an independent statement rather than a restatement
  /// of the implementation.
  @Test func everyWeightHalfIsPinnedFromBothSidesInTheTable() {
    for weight in WashLabelWeight.allCases {
      let rows = Self.washLabelBoundaryCases.filter { $0.weight == weight }
      #expect(rows.contains { $0.isNormalText }, "no admitted boundary row for \(weight)")
      #expect(rows.contains { !$0.isNormalText }, "no rejected boundary row for \(weight)")
    }
  }

  /// ``WashLabelWeight/init(_:)`` is what lets a token-backed row take its
  /// weight live instead of transcribing it, so this pins every mapping the
  /// fixtures rely on. The `.medium` pin is the one doing real work: `.medium`
  /// and `.regular` share the ≥18pt half, so a mapping that folded `.medium`
  /// into `.regular` would produce identical results everywhere else in the
  /// repo — this pin is the only thing that observes the distinction between
  /// naming `.medium` explicitly and defaulting it there by accident.
  ///
  /// This no longer probes the unmodelled-weight path: all nine named
  /// `Font.Weight` statics are modelled now, and `Font.Weight` has no public
  /// initializer, so no unmodelled weight can be constructed to drive it. The
  /// `default:` arm's `Issue.record` in ``WashLabelWeight/init(_:)`` is
  /// therefore unobservable by test — it stays in place as a guard for a
  /// future SwiftUI weight, not as something this suite can exercise.
  @Test func tokenWeightsMapToHalves() {
    #expect(WashLabelWeight(.regular) == .regular)
    #expect(WashLabelWeight(.medium) == .medium)
    #expect(WashLabelWeight(.semibold) == .semibold)
    #expect(WashLabelWeight(.bold) == .bold)
    #expect(WashLabelWeight(.heavy) == .bold)
  }

  /// The negative control for ``MossWashSite/isNormalText``.
  ///
  /// The per-row assertion in `mossOnWashClearsAAOnEveryWashItIsUsedOn` passes
  /// on every shipped row and would go on passing if `isNormalText` were wired
  /// to a threshold twice as large, or to the wrong field — a guard's passing
  /// case proves nothing. This constructs the rows the guard claims to reject
  /// and confirms it does.
  @Test func mossWashSiteRejectsLargeTextLabels() {
    #expect(Self.washLabelBoundaryCases.count == 9)

    for probe in Self.washLabelBoundaryCases {
      let row = MossWashSite(
        "probe", wash: .moss, light: 0.20, dark: 0.20,
        pointSize: probe.pointSize, weight: probe.weight)
      #expect(
        row.isNormalText == probe.isNormalText,
        "\(probe.pointSize)pt \(probe.weight): expected isNormalText == \(probe.isNormalText)")
    }
  }

  /// The negative control for ``InkWashSite/isNormalText``, and deliberately a
  /// second one rather than a reuse of the moss control above: the two row types
  /// forward the same fields to the same ``WashLabelWeight`` method, so sharing
  /// would look sufficient — but what each type can get wrong is its own wiring,
  /// and a control run through a sibling that happens to be correct passes
  /// without observing this one at all.
  @Test func inkWashSiteRejectsLargeTextLabels() {
    #expect(Self.washLabelBoundaryCases.count == 9)

    for probe in Self.washLabelBoundaryCases {
      let row = InkWashSite(
        "probe", alpha: 0.15, pointSize: probe.pointSize, weight: probe.weight)
      #expect(
        row.isNormalText == probe.isNormalText,
        "\(probe.pointSize)pt \(probe.weight): expected isNormalText == \(probe.isNormalText)")
    }
  }
}

// MARK: - Helpers

/// The WCAG 1.4.3 weight halves, as the wash fixtures record them.
///
/// "Large text" is a two-valued threshold — ≥14pt **bold**, ≥18pt otherwise —
/// so a row's point size alone cannot decide which bar applies to it. This is
/// the other half of that decision, and the reason the fixtures store a weight
/// rather than a point size on its own.
///
/// **`.semibold` takes the ≥18pt half, decided here rather than per row.**
/// WCAG's "bold" is conventionally ≥700 and `.semibold` is 600, so the ≥14pt
/// half would be the more permissive reading of a weight WCAG does not call
/// bold. #1466 settled that as a convention in prose;
/// ``DesignTokensTests/mossWashSiteRejectsLargeTextLabels`` is where it became
/// executable, separating it from `.bold` *and* pinning the value.
///
/// **What makes the choice safe is a property, not a preference**: the fixtures
/// pin one bar, the strictest available, and a row failing the criterion is a
/// red rather than a silent drop. So *every* misclassification this type can
/// produce errs toward over-strictness — none routes a label to a *looser* bar,
/// because no looser bar exists in these files.
///
/// Four weights are modelled now, covering every weight the fixtures in this
/// suite use. `.medium` (500) takes the ≥18pt half alongside `.regular` and
/// `.semibold`, decided here rather than per row: WCAG's "bold" is
/// conventionally ≥700, and `.semibold` (600) already takes the ≥18pt half, so
/// `.medium` cannot take the bold half either — and as with every case here,
/// the classification errs toward over-strictness, never the other way. Both
/// the `largeTextThreshold` switch and ``init(_:)`` are written so a new weight
/// cannot arrive without that decision — the first by having no `default:`, the
/// second by recording an issue.
///
/// The live case `.medium` serves: `PredictionOutcomeBadge`'s streak
/// sub-label, `.caption.weight(.medium)`
/// (`Views/Components/PredictionOutcomeBadge.swift`).
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
enum WashLabelWeight: CaseIterable {
  case regular
  case medium
  case semibold
  case bold

  /// The half a design-token weight selects, **derived rather than
  /// transcribed** — so a row whose view reads a `Typography.*` token can take
  /// both of its figures live, the way it already takes `size`.
  ///
  /// Records an issue rather than folding an unmodelled weight into `.regular`:
  /// silently defaulting is safe in outcome but erases the "a new weight is a
  /// decision" property this type exists to hold.
  init(_ weight: Font.Weight) {
    switch weight {
    case .bold, .heavy, .black: self = .bold
    case .semibold: self = .semibold
    case .medium: self = .medium
    case .regular, .light, .thin, .ultraLight: self = .regular
    default:
      Issue.record("unmodelled Font.Weight — decide its WCAG half in WashLabelWeight")
      self = .regular
    }
  }

  /// The point size **at or above which** a label of this weight is WCAG large
  /// text, i.e. answers to the 3:1 bar instead of 4.5:1.
  var largeTextThreshold: Double {
    switch self {
    case .bold: 14
    case .regular, .medium, .semibold: 18
    }
  }

  /// Whether a label at `pointSize` is still normal text under this weight.
  ///
  /// Strict `<`: WCAG's thresholds are inclusive, so a 14pt bold label *is*
  /// large text and must not be admitted to a normal-text fixture.
  func admitsAsNormalText(pointSize: Double) -> Bool { pointSize < largeTextThreshold }
}

/// The failure message the fixtures share when a row is large text.
///
/// One wording in one place: several byte-identical string literals across
/// files would be a mirror like any other.
///
/// **It carries the repair direction because the cheapest repair is wrong.**
/// `#expect` does not short-circuit, so a rejected row reddens twice — here,
/// then on the 4.5 assertions it is not exempt from — and both `pointSize` and
/// `weight` are recorded by hand, so editing the record is the path of least
/// resistance out of the red and nothing would catch it.
/// `DesignTokensTests+MossInkAsWashLabel.swift`'s "Large text is out" bullet is
/// where a genuinely large-text site goes instead.
func largeTextRejection(_ name: String, pointSize: Double, weight: WashLabelWeight) -> String {
  """
  \(name) is large text (\(pointSize)pt \(weight)) and does not belong in a normal-text fixture \
  — measure it at WCAG 1.4.11's 3:1 or exclude it deliberately; do not adjust the recorded \
  size/weight to clear this
  """
}

/// Point sizes of the semantic SwiftUI text styles the wash fixtures use, at
/// the default `.large` content size — and the reference for what a row's
/// `pointSize` means in either regime, for every row type in this suite.
///
/// **The split is fixed-size vs scaling, not which expression the view wrote.**
/// *Fixed size* covers every `.system(size:)` label — from a `Typography.*`
/// token (referenced live via the token's `size`, and fixed-size by design per
/// ``PasturaTextStyle/font``), a layout constant read live
/// (`HomeHeroLayout.*FontSize`), or a literal the view inlines; for those the
/// recorded value is the size at every content size. *Scaling* covers the two
/// constants below, whose value is the size **at the default**: at accessibility
/// sizes such a label crosses into large text, which only **relaxes** the bar
/// the fixtures apply. So a row's `pointSize` decides admission at the default
/// and nothing else.
///
/// **Hand-recorded against the view, and a wrong transcription is caught by
/// nothing.** Live references, ``WashLabelWeight/init(_:)`` and
/// ``DesignTokensTests/semanticLabelSizesMatchUIKitAtTheDefaultContentSize``
/// remove the guesswork from every figure that has a source — which is why
/// these two are measured here rather than written down. But *which* figure a
/// row takes is still a reader's judgement: a reviewer has to open the view
/// when a row is added.
enum WashLabelSemanticSize {
  static let caption = 12.0
  static let caption2 = 11.0
}

/// One boundary case for the ``WashLabelWeight`` halves: a point size, a
/// weight, and whether the pair is still normal text.
///
/// A struct rather than a tuple because swiftlint's `large_tuple` caps tuples
/// at two members. Same reason as ``MossWashSite``.
struct WashLabelBoundaryCase {
  let pointSize: Double
  let weight: WashLabelWeight
  let isNormalText: Bool

  init(_ pointSize: Double, _ weight: WashLabelWeight, isNormalText: Bool) {
    self.pointSize = pointSize
    self.weight = weight
    self.isNormalText = isNormalText
  }
}
