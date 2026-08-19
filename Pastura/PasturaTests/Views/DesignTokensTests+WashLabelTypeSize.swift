import SwiftUI
import Testing
import UIKit

@testable import Pastura

// The WCAG large-text admission criterion the wash-contrast fixtures apply,
// made executable (#1468).
//
// `DesignTokensTests+MossOnWash.swift`, `+MossInkAsWashLabel.swift` and
// `+InkOnWash.swift` each pin a 4.5:1 bar, and each is only the right bar
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
// **Two sibling fixtures in this suite still carry the unexecuted form, and the
// class is not closed** (#1495). `DesignTokensTests+MossSoftGround.swift`'s
// `textBar` pins 4.5 over a `[String]` site list and keeps a superlative on top
// of it — the exact state #1466 falsified — and
// `DesignTokensTests+MutedAsContent.swift`'s `contentTextBar` carries the
// shorter form. They are excluded here rather than overlooked, and **one
// obstacle is common to both**: `PredictionOutcomeBadge`'s streak sub-label is
// `.caption.weight(.medium)`, and both fixtures speak for it — so either would
// force a fourth ``WashLabelWeight`` case, i.e. a WCAG judgement call this
// branch had no occasion to make. On top of that the first needs its `[String]`
// list promoted to a row type, and the second's remaining claim is entangled
// with the occupancy question it explicitly defers to #1448. Do not read the
// criterion below as covering either.
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
  /// green a red disarms them together.** That is the failure to guard against
  /// — not sabotage, just the ordinary red-test reflex: someone re-deciding a
  /// half edits ``WashLabelWeight/largeTextThreshold``, sees three reds, and
  /// "fixes" the expectations. No shipped row would redden alongside, since all
  /// of them sit far from either threshold.
  /// ``everyWeightHalfIsPinnedFromBothSidesInTheTable`` is what makes a *lost*
  /// pin visible; a row *moved* (18 → 19) still passes it, and the count pin
  /// below survives any same-cardinality swap.
  static let washLabelBoundaryCases: [WashLabelBoundaryCase] = [
    WashLabelBoundaryCase(14, .bold, isNormalText: false),
    WashLabelBoundaryCase(13.9, .bold, isNormalText: true),
    WashLabelBoundaryCase(14, .semibold, isNormalText: true),
    WashLabelBoundaryCase(18, .semibold, isNormalText: false),
    WashLabelBoundaryCase(17.9, .semibold, isNormalText: true),
    WashLabelBoundaryCase(18, .regular, isNormalText: false),
    WashLabelBoundaryCase(17.9, .regular, isNormalText: true)
  ]

  /// The two semantic sizes are the only figures in any wash fixture with no
  /// token to reference, so they are measured rather than asserted in prose —
  /// a literal plus "iOS default Large" in a doc comment would be the same
  /// shape of claim #1468 is retiring.
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
  /// `count == 7` survives a same-cardinality swap, and says nothing at all
  /// about a **fourth** ``WashLabelWeight`` case, which would ship with zero
  /// control rows while both negative controls stayed green.
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
  /// weight live instead of transcribing it, so this pins both halves of that
  /// initializer: the mappings the fixtures rely on, and — through
  /// `withKnownIssue` — that an unmodelled weight is *recorded* rather than
  /// quietly folded into `.regular`.
  ///
  /// The second half is the one that matters. Defaulting silently would still
  /// be the over-strict direction, so no arm would ever redden to reveal it,
  /// and the "a fourth weight is a decision" property would be gone with
  /// nothing to show for it.
  @Test func tokenWeightsMapToHalvesAndUnmodelledOnesAreRecorded() {
    #expect(WashLabelWeight(.regular) == .regular)
    #expect(WashLabelWeight(.semibold) == .semibold)
    #expect(WashLabelWeight(.bold) == .bold)
    #expect(WashLabelWeight(.heavy) == .bold)

    withKnownIssue("an unmodelled weight must record an issue, not default silently") {
      _ = WashLabelWeight(.medium)
    }
  }

  /// The negative control for ``MossWashSite/isNormalText``.
  ///
  /// The per-row assertion in `mossOnWashClearsAAOnEveryWashItIsUsedOn` passes
  /// on every shipped row and would go on passing if `isNormalText` were wired
  /// to a threshold twice as large, or to the wrong field — a guard's passing
  /// case proves nothing. This constructs the rows the guard claims to reject
  /// and confirms it does.
  ///
  /// Deliberately **not** shared with the ink control: each row type stores and
  /// forwards its own two fields, and a control borrowed from a sibling type
  /// stops discriminating the moment that sibling is the one wired correctly.
  @Test func mossWashSiteRejectsLargeTextLabels() {
    #expect(Self.washLabelBoundaryCases.count == 7)

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
  /// second one rather than a reuse of the moss control above.
  ///
  /// The two row types forward the same two fields to the same
  /// ``WashLabelWeight`` method, so a shared control would look sufficient —
  /// but what each type can get wrong is its own wiring, and a control run
  /// through a sibling that happens to be correct passes without observing this
  /// one at all.
  @Test func inkWashSiteRejectsLargeTextLabels() {
    #expect(Self.washLabelBoundaryCases.count == 7)

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
/// bold. #1466 settled that as a convention in prose; this is where it became
/// executable — ``DesignTokensTests/mossWashSiteRejectsLargeTextLabels``
/// separates it from `.bold` *and* pins the value, which a lone `14pt semibold`
/// case could not.
///
/// **What makes the choice safe is a property, not a preference**: the fixtures
/// pin one bar, the strictest available, and a row failing the criterion is a
/// red rather than a silent drop. So *every* misclassification this type can
/// produce errs toward over-strictness — a row wrongly on the ≥18 half is held
/// to 4.5 where WCAG would allow 3:1, and one wrongly on ≥14 reddens and gets
/// looked at. No misclassification routes a label to a *looser* bar, because no
/// looser bar exists in these files.
///
/// Only the three weights the fixtures use are modelled, and a fourth is a
/// decision rather than a mechanical addition — it has to choose a half. Both
/// the `largeTextThreshold` switch and ``init(_:)`` are written so that a new
/// weight cannot arrive without one being made (the first by having no
/// `default:`, the second by recording an issue). A live case in the tree
/// waiting on that decision: `PredictionOutcomeBadge`'s streak sub-label is
/// `.caption.weight(.medium)` (#1495).
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
enum WashLabelWeight: CaseIterable {
  case regular
  case semibold
  case bold

  /// The half a design-token weight selects, **derived rather than
  /// transcribed** — so a row whose view reads a `Typography.*` token can take
  /// both of its figures live, the way it already takes `size`.
  ///
  /// Records an issue rather than folding an unmodelled weight into `.regular`:
  /// silently defaulting would be the over-strict direction and therefore safe
  /// in outcome, but it would erase the "a fourth weight is a decision"
  /// property this type exists to hold. `.medium` is the case that would hit it
  /// today.
  init(_ weight: Font.Weight) {
    switch weight {
    case .bold, .heavy, .black: self = .bold
    case .semibold: self = .semibold
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
    case .regular, .semibold: 18
    }
  }

  /// Whether a label at `pointSize` is still normal text under this weight.
  ///
  /// Strict `<`: WCAG's thresholds are inclusive, so a 14pt bold label *is*
  /// large text and must not be admitted to a normal-text fixture.
  func admitsAsNormalText(pointSize: Double) -> Bool { pointSize < largeTextThreshold }
}

/// The failure message the three wash fixtures share when a row is large text.
///
/// One wording in one place: the criterion lives here, so a message that drifts
/// per fixture is the plausible failure — three byte-identical string literals
/// across files are a mirror like any other.
///
/// **It carries the repair direction because the cheapest repair is wrong.**
/// A rejected row reddens twice (this arm, then the 4.5 assertions it is not
/// exempt from), and both `pointSize` and `weight` are recorded by hand — so
/// editing the record is the path of least resistance out of the red, and
/// nothing would catch it. `DesignTokensTests+MossInkAsWashLabel.swift`'s
/// "Large text is out" bullet is where a genuinely large-text site goes.
func largeTextRejection(_ name: String, pointSize: Double, weight: WashLabelWeight) -> String {
  """
  \(name) is large text (\(pointSize)pt \(weight)) and does not belong in a normal-text fixture \
  — measure it at WCAG 1.4.11's 3:1 or exclude it deliberately; do not adjust the recorded \
  size/weight to clear this
  """
}

/// Point sizes of the semantic SwiftUI text styles the wash fixtures use, at
/// the default `.large` content size — and the reference for what a row's
/// `pointSize` means in either regime, for both ``MossWashSite`` and
/// ``InkWashSite``.
///
/// **The split is fixed-size vs scaling, not which expression the view wrote.**
///
/// *Fixed size* covers every `.system(size:)` label — from a `Typography.*`
/// token (referenced live via the token's `size`, and fixed-size by design per
/// ``PasturaTextStyle/font``), from a layout constant read live
/// (`HomeHeroLayout.*FontSize`), or from a literal the view inlines. For those
/// the recorded value is the size at every content size.
///
/// *Scaling* covers the two constants below. Their value is the size **at the
/// default**: at accessibility sizes such a label crosses into large text,
/// which only **relaxes** the bar the fixtures apply. So a row's `pointSize`
/// decides admission at the default and nothing else.
///
/// **Hand-recorded against the view, and a wrong transcription is caught by
/// nothing.** Live references, ``WashLabelWeight/init(_:)`` and
/// ``DesignTokensTests/semanticLabelSizesMatchUIKitAtTheDefaultContentSize``
/// remove the guesswork from every figure that has a source — which is why
/// these two are measured here rather than written down. But *which* figure a
/// row takes is still a reader's judgement, the same standing the fixtures give
/// their grounds. A reviewer has to open the view when a row is added.
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
