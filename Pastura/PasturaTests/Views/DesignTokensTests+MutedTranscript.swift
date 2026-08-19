//
// The doc-transcript half of `DesignTokensTests+MutedAsContent` (#1488): the
// three-digit figures `docs/**` prints, pinned as data and compared against what
// the sibling file computes.
//
// Sibling-file extension rather than a fresh `@Suite`, per
// `.claude/rules/testing.md` § "Splitting a Suite Across Files"; the grounds and
// wash arrays live next door and are `internal` for that reason.
//
// ⚠️ **`scripts/check-measurement-transcripts.py` anchors on this file by
// path and on two declarations by name** — `FIXTURE_PATH`, `OPAQUE_DECL`,
// `WASH_DECL`. Renaming this file, or renaming/relaxing the `private static let`
// on ``opaqueGroundPins`` / ``washRowPins``, makes the checker raise rather than
// pass emptily; repoint those three constants in the same commit.

import SwiftUI
import Testing

@testable import Pastura

extension DesignTokensTests {

  // MARK: - Doc transcript pins (#1488)

  /// The figures `docs/design/muted-application-audit.md` §3.1 / §3.2 print,
  /// pinned here so those tables are checkable transcripts rather than a second
  /// source.
  ///
  /// Keyed by **stable tokens** — ground token names and site *type* names —
  /// never by the doc's Site-column prose, which is free to be reworded, and
  /// never by array index: the wash arrays are grouped by wash kind rather than
  /// by site, so an index map repoints silently when a row is added.
  ///
  /// **A failure means the palette moved; it is not a defect** — these are
  /// measurements, so the response is to re-record. The failure message prints
  /// the recovery, and green certifies the arithmetic only, not that a row
  /// describes the right site. Procedure:
  /// `muted-application-audit.md` § "Regenerating the ratio tables".
  ///
  /// Comparison is by the doc's own rounding — `(x * 1000).rounded() / 1000` —
  /// rather than an epsilon: one wide enough to absorb the printed rounding is
  /// also wide enough to hide a genuine move.
  private static let opaqueGroundPins: [(name: String, ratio: Double)] = [
    ("screenBackground", 3.329),
    ("page", 3.030),
    ("bubbleBackground", 3.475),
    ("whisperBubble", 2.953),
    ("promoBackground", 3.319),
    ("mossSoft", 2.136),
    ("nightBackground", 3.779),
    ("nightPage", 4.152),
    ("nightBubble", 3.021),
    ("nightWhisperBubble", 2.783),
    ("nightPromoBackground", 3.161),
    ("nightMossSoft", 2.413)
  ]

  /// §3.2's five rows. Each appearance is an **interval** because one row is
  /// genuinely one: four sites composite over a single known ground and collapse
  /// to a point (`min == max`), while `ReportSheet` renders on the system sheet
  /// surface, which is not a Pastura token, so its row quantifies over the
  /// twelve instead.
  ///
  /// **`ReportSheet`'s interval is the min/max of ``mutedRuleWashGrounds``, not
  /// of ``mutedRuleWashBrackets``.** Light alone cannot settle that: its upper
  /// end agrees to three digits with the light-over-**white** bracket, an
  /// artefact of `screenBackground` (#FCFAF4) being nearly white. Dark is what
  /// discriminates — it lands nowhere near the dark-over-black bracket.
  ///
  /// A named struct rather than a triple: three members trip `large_tuple`, and
  /// the labels are what `scripts/check-measurement-transcripts.py` keys on.
  private struct WashRowPin {
    let site: String
    let light: (min: Double, max: Double)
    let dark: (min: Double, max: Double)
  }

  private static let washRowPins: [WashRowPin] = [
    WashRowPin(site: "ResultsView", light: (2.895, 2.895), dark: (3.239, 3.239)),
    WashRowPin(site: "ActiveModelChip", light: (2.953, 2.953), dark: (3.098, 3.098)),
    WashRowPin(site: "ModelRow", light: (3.287, 3.287), dark: (2.693, 2.693)),
    WashRowPin(site: "ReportSheet", light: (2.300, 3.018), dark: (2.520, 3.503)),
    WashRowPin(site: "HighlightShareCard", light: (2.932, 2.932), dark: (3.140, 3.140))
  ]

  /// The four bracket figures. Two are quoted in **prose** rather than a table —
  /// ``mutedRuleWashBrackets``' own doc comment, and
  /// ``compositedGroundsStayAboveTheOpaqueWorstCase``'s reason for excluding the
  /// brackets. Pinned for exactly that reason: a prose figure has no table to be
  /// re-derived from, so it is the shape most likely to rot.
  private static let ruleWashBracketPins: [(name: String, ratio: Double)] = [
    ("light rule@0.45 over pure white", 3.018),
    ("light rule@0.45 over pure black", 1.739),
    ("dark nightRule@0.45 over pure white", 1.825),
    ("dark nightRule@0.45 over pure black", 3.919)
  ]

  /// The docs' rounding, applied to a computed ratio.
  private static func rounded3(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
  }

  /// The same rounding the comparison uses, then formatted. `%.3f` on the raw
  /// value would resolve an exact tie half-to-even while `rounded3` resolves it
  /// half-away-from-zero, so an `x.xxx5` figure could print a literal the
  /// comparator still rejects — a paste-back loop that never converges.
  private static func printed3(_ value: Double) -> String {
    String(format: "%.3f", rounded3(value))
  }

  /// The computed interval for a ``washRowPins`` site, resolved by the site
  /// token embedded in each wash entry's name. `nil` when no entry carries the
  /// token, which the arm below reports as a divergence rather than skipping.
  private static func computedWashRow(_ site: String)
    -> (light: (min: Double, max: Double), dark: (min: Double, max: Double))? {
    let all = mutedSelfWashGrounds + mutedMossWashGrounds + mutedRuleWashGrounds
    func interval(_ appearance: String) -> (min: Double, max: Double)? {
      let ratios =
        all
        .filter { $0.name.hasPrefix("\(appearance) ") && $0.name.contains(" \(site) ") }
        .map(\.ratio)
      guard let low = ratios.min(), let high = ratios.max() else { return nil }
      return (low, high)
    }
    guard let light = interval("light"), let dark = interval("dark") else { return nil }
    return (light, dark)
  }

  /// Diverging `(name, ratio)` pins, as paste-back literals. Shared by the
  /// §3.1 grounds and the brackets — same pin shape, same recovery.
  private static func staleRatioPins(
    computed: [(name: String, ratio: Double)], pins: [(name: String, ratio: Double)]
  ) -> [String] {
    computed.compactMap { entry in
      guard let pin = pins.first(where: { $0.name == entry.name }),
        rounded3(entry.ratio) != pin.ratio
      else { return nil }
      return "    (\"\(entry.name)\", \(printed3(entry.ratio))),"
    }
  }

  /// Diverging §3.2 rows, as paste-back literals. A site whose token no longer
  /// appears in any wash entry is reported rather than skipped — silently
  /// dropping it is the failure mode the bijection assertions bar elsewhere.
  private static func staleWashRowPins() -> [String] {
    washRowPins.compactMap { pin in
      guard let got = computedWashRow(pin.site) else {
        return "    // \(pin.site): no wash entry carries this site token"
      }
      let moved =
        rounded3(got.light.min) != pin.light.min || rounded3(got.light.max) != pin.light.max
        || rounded3(got.dark.min) != pin.dark.min || rounded3(got.dark.max) != pin.dark.max
      guard moved else { return nil }
      return "    WashRowPin(site: \"\(pin.site)\", light: (\(printed3(got.light.min)), "
        + "\(printed3(got.light.max))), dark: (\(printed3(got.dark.min)), "
        + "\(printed3(got.dark.max)))),"
    }
  }

  /// Pins whose recomputed figure is **lower** than what is pinned.
  ///
  /// Split out because the three arms that floor part of this population leave
  /// most of it uncovered and are easy to over-credit — ``quieterCallOut``
  /// enumerates which, since that is what a failing author reads. The remaining
  /// floors (`>= 4.5`) are for the *replacement* tokens, and the rest bound
  /// `muted` from above (sub-AA), which a downward drift satisfies more
  /// comfortably. So for an uncovered figure this arm is the only red, and its
  /// own instruction — paste the new figures in — accepts the regression:
  /// naming the direction is what turns a re-record into a decision. A *raised*
  /// figure needs no call-out; the sub-AA arms already bound it.
  private static func quieterThanPinned(
    computed: [(name: String, ratio: Double)], pins: [(name: String, ratio: Double)]
  ) -> [String] {
    computed.compactMap { entry in
      guard let pin = pins.first(where: { $0.name == entry.name }), rounded3(entry.ratio) < pin.ratio
      else { return nil }
      return "    \(entry.name): \(printed3(entry.ratio)) — was \(String(format: "%.3f", pin.ratio))"
    }
  }

  /// The same direction test for §3.2, on **both** ends of each row.
  ///
  /// Not the lower end alone: four rows collapse to a point, but `ReportSheet`
  /// quantifies over the twelve, so its ends come from *different* grounds and
  /// retuning only the one behind the upper end lowers that end with the lower
  /// one unchanged. A min-only test would miss exactly the row it was written
  /// for.
  private static func quieterWashRows() -> [String] {
    washRowPins.compactMap { pin in
      guard let got = computedWashRow(pin.site) else { return nil }
      let ends = [
        ("light min", got.light.min, pin.light.min), ("light max", got.light.max, pin.light.max),
        ("dark min", got.dark.min, pin.dark.min), ("dark max", got.dark.max, pin.dark.max)
      ]
      let moved = ends.filter { rounded3($0.1) < $0.2 }
        .map { "\($0.0) \(printed3($0.1)) — was \(String(format: "%.3f", $0.2))" }
      return moved.isEmpty ? nil : "    \(pin.site): \(moved.joined(separator: ", "))"
    }
  }

  /// The direction paragraph appended to a failure, empty when nothing dropped.
  private static func quieterCallOut(opaque: [(name: String, ratio: Double)]) -> String {
    let quieter =
      quieterThanPinned(computed: opaque, pins: opaqueGroundPins)
      + quieterWashRows()
      + quieterThanPinned(computed: mutedRuleWashBrackets, pins: ruleWashBracketPins)
    guard !quieter.isEmpty else { return "" }
    return """


      ⚠️ \(quieter.count) of them moved DOWN — less contrast than was recorded. Three arms floor \
      part of that and none covers all of it: the span arm pins only the opaque min and max; \
      `compositedGroundsStayAboveTheOpaqueWorstCase` floors the washes only RELATIVE to that \
      opaque worst, so a drift lowering both stays green there; and \
      `nightPageIsTheGroundNearestTheBar` catches a ground only once it overtakes a neighbour. \
      No other arm floors a pinned figure. For anything outside those three, this arm is the \
      only red and pasting the new figures in is what accepts the regression. Decide that \
      deliberately — if the retune was not meant to reach these grounds, fix the palette \
      instead of the pins.

      \(quieter.joined(separator: "\n"))
      """
  }

  /// Every figure the docs transcribe, recomputed and compared at the docs' own
  /// precision. The bijection assertions are not decoration: comparing only the
  /// pins that find a computed twin would let a renamed ground drop out while
  /// this arm stayed green.
  @Test func docTranscriptsMatchTheComputedFigures() {
    #expect(Self.opaqueGroundPins.count == 12)
    #expect(Self.washRowPins.count == 5)
    #expect(Self.ruleWashBracketPins.count == 4)

    let opaque = Self.mutedLightGrounds + Self.mutedDarkGrounds
    #expect(
      Set(Self.opaqueGroundPins.map(\.name)) == Set(opaque.map(\.name)),
      "§3.1 pins and the computed grounds no longer name the same twelve")
    // The wash rows' other direction: `staleWashRowPins` walks the *pins*, so a
    // new site could be measured and never transcribed. Stated as "entries with
    // no pin" rather than a set equality over resolved sites — the set form
    // cannot fire, since an unmatched entry drops out and both sides shrink
    // together.
    let washEntries =
      Self.mutedSelfWashGrounds + Self.mutedMossWashGrounds + Self.mutedRuleWashGrounds
    let unpinnedWashEntries = washEntries.filter { entry in
      !Self.washRowPins.contains { entry.name.contains(" \($0.site) ") }
    }
    .map(\.name)
    #expect(
      unpinnedWashEntries.isEmpty,
      "wash entries whose site has no pin: \(unpinnedWashEntries)")

    // `computedWashRow` resolves on TWO conjuncts — appearance prefix and site
    // token — so checking only the site leaves a seam: `"Light ResultsView …"`
    // counts as pinned above, feeds no interval there, and `staleWashRowPins`'
    // `nil` branch stays quiet because correctly-prefixed siblings keep the
    // match non-nil.
    let misprefixed = washEntries.map(\.name).filter {
      !$0.hasPrefix("light ") && !$0.hasPrefix("dark ")
    }
    #expect(misprefixed.isEmpty, "wash entries with no appearance prefix: \(misprefixed)")

    #expect(
      Set(Self.ruleWashBracketPins.map(\.name)) == Set(Self.mutedRuleWashBrackets.map(\.name)),
      "bracket pins and the computed brackets no longer name the same four")

    let stale =
      Self.staleRatioPins(computed: opaque, pins: Self.opaqueGroundPins)
      + Self.staleWashRowPins()
      + Self.staleRatioPins(
        computed: Self.mutedRuleWashBrackets, pins: Self.ruleWashBracketPins)

    #expect(
      stale.isEmpty,
      """
      The palette moved: \(stale.count) pinned figure(s) no longer match what this file \
      computes. That is a re-record, not a defect. Paste the lines below over their pins above, \
      then carry the same three-digit figures into the doc faces that transcribe them — \
      `python3 scripts/check-measurement-transcripts.py --check` names those faces and stays red \
      until they agree.

      \(stale.joined(separator: "\n"))\(Self.quieterCallOut(opaque: opaque))
      """)
  }

  /// §3.1's span sentence is a *derived* figure, not a thirteenth measurement:
  /// the min and max of the twelve. `scripts/check-measurement-transcripts.py`
  /// re-derives it from the pins for that reason; this arm is what makes the
  /// derivation checked rather than assumed.
  @Test func theSpanIsTheMinAndMaxOfTheTwelve() {
    let ratios = Self.opaqueGroundPins.map(\.ratio)
    #expect(ratios.min() == 2.136)
    #expect(ratios.max() == 4.152)
  }
}
