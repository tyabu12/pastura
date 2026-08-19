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
// large-text row would have been admitted silently. #1466 is the demonstration:
// a superlative in `textBar`'s doc survived until a new 12pt row falsified it,
// and only a hand census of all nine rows caught that — while a second claim
// citing it in `+InkOnWash.swift` went stale at the same moment.
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
// shorter form. They are excluded here rather than overlooked, and for
// different reasons: the first would need its list promoted to a row type, and
// the second stores **grounds** rather than labels, so there is no row for a
// font to hang on and its claim needs a fixture that does not exist yet. Do not
// read the criterion below as covering either.
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
/// bold; the ≥18pt half holds a semibold row to the stricter 4.5:1 bar for
/// longer. #1466 settled that as a convention in prose; this is where it became
/// executable — ``DesignTokensTests/mossWashSiteRejectsLargeTextLabels``
/// separates it from `.bold` *and* pins the value, which a lone `14pt semibold`
/// case could not.
///
/// Only the three weights the fixtures actually use are modelled. A fourth
/// (`.heavy`, `.medium`, ...) is a decision rather than a mechanical addition —
/// it has to choose a half — so it belongs in this switch, not at a call site.
///
/// File scope per `.claude/rules/testing.md` § "Splitting a Suite Across Files":
/// helpers in a sibling file live outside the suite struct.
enum WashLabelWeight {
  case regular
  case semibold
  case bold

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
func largeTextRejection(_ name: String, pointSize: Double, weight: WashLabelWeight) -> String {
  "\(name) is large text (\(pointSize)pt \(weight)) and does not belong in a normal-text fixture"
}

/// Point sizes of the semantic SwiftUI text styles the wash fixtures use, at
/// the default `.large` content size.
///
/// Rows on a `.system(size:)` label carry that size instead — from a
/// `Typography.*` token, a layout constant, or a literal the view inlines — and
/// those are fixed-size by design (``PasturaTextStyle/font``'s doc comment), so
/// the value is the size, full stop. These two have no such value to read,
/// which is why they are named here and measured by
/// ``DesignTokensTests/semanticLabelSizesMatchUIKitAtTheDefaultContentSize``
/// rather than written down.
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
