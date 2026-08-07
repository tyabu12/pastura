import SwiftUI

/// A curated highlight's excerpt, drawn the way the app draws a live run
/// (ADR-029).
///
/// The excerpt used to render as a bare name-above-line list, so the one place
/// a browsing user saw Pastura actually running looked nothing like Pastura
/// running. This wraps it in a panel that reuses the real components rather
/// than imitating them: ``LeafIcon`` and `GameHeader`'s round label in the
/// head, ``AgentOutputRow`` for every line, ``PasturaStreamDivider`` at a round
/// boundary. `web/src/components/ScenarioLanding.astro` makes the same move for
/// the landing pages, but has to reimplement the vocabulary in CSS; here the
/// originals are in reach, so a reader sees the same pixels they will see after
/// installing.
///
/// ## Static by construction (ADR-029 Decision 6)
///
/// Decision 6 keeps highlights outside the Phase-3 replay deferral only while
/// nothing here executes, plays back, or seeks. ``AgentOutputRow`` is the *live
/// simulation* row and carries all of those affordances, so the configuration
/// below is load-bearing, not incidental:
///
/// - `charsPerSecond: nil` — `shouldAnimate` is `false`, so the row snaps to
///   full text on appear and the typewriter never runs.
/// - **No `inner_thought` in the fields dictionary** — this, and *not*
///   `showAllThoughts: false`, is what suppresses the `INNER VOICE` chevron:
///   the toggle renders only when `resolvedThought` is non-empty. Decision 3
///   keeps thoughts out of an excerpt, so a toggle here would be an affordance
///   with nothing behind it. ⚠️ Adding a thought field to enrich the excerpt
///   would silently re-open a Decision-6 affordance — no compile error, no
///   failing test.
/// - `onAvatarTap` / `onShareHighlight` omitted — both are `if let`-gated
///   inside the row, so leaving them nil drops the persona sheet and the share
///   button rather than merely hiding them.
struct GalleryHighlightRunFigure: View {

  let excerpt: [GalleryHighlightExcerptEntry]

  /// The scenario's round count, or `nil` when the feed omits it — the head's
  /// round fragment then collapses and dividers drop the total.
  let totalRounds: Int?

  /// Inset panel radius. Smaller than the enclosing `PasturaCard`'s 14 so the
  /// figure reads as sitting *inside* the card rather than tracing its edge.
  private static let cornerRadius: CGFloat = 12

  var body: some View {
    let rows = GalleryScenarioDetailFormat.excerptRows(excerpt, totalRounds: totalRounds)
    // Empty only if every phase failed to map, which `GalleryHighlightLoader`
    // has already hidden the whole highlight for — so this renders nothing
    // rather than an empty panel, and never fires in production.
    if !rows.isEmpty {
      VStack(spacing: 0) {
        head
        stream(rows)
      }
      // `screenBackground` inside the card's `bubbleBackground` reads as inset
      // in both appearances: lighter-on-white in light, darker-on-`nightBubble`
      // in dark. Both tokens are paired, so this is an ambient surface and
      // correctly follows the device (ADR-028) — no fixed-appearance pinning,
      // unlike `HighlightShareCard`, which exports through `ImageRenderer`.
      .background(Color.screenBackground)
      .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
          .stroke(Color.rule, lineWidth: 1)
      )
      // Render probe for `GalleryHighlightRenderTests`. A render crash in this
      // subtree is invisible to `xcodebuild build` and the unit suite alike
      // (swiftui-traps.md § "iOS 26 AttributeGraph crash"), so a UI test that
      // navigates in and looks for this identifier is the only signal.
      //
      // This container is not itself an accessibility element, so the
      // identifier does not publish one queryable element — it propagates to
      // every leaf below. The test therefore matches type-agnostically;
      // `app.otherElements[…]` finds nothing even when the figure is fully
      // drawn. Do NOT "fix" that by adding `.accessibilityElement(children:)`
      // here: that would collapse the rows into one VoiceOver stop and undo
      // `AgentOutputRow`'s per-utterance grouping.
      .accessibilityIdentifier("galleryDetail.highlightRunFigure")
    }
  }

  /// Leaf + round + the RECORDED pill, echoing `GameHeader`'s title row.
  ///
  /// The phase is deliberately absent, unlike `GameHeader`'s meta row and
  /// unlike the web figure's head: every row below carries its own
  /// `PhaseTypeLabel`, so naming it here would say the same thing twice. The
  /// web has no per-row badge, which is why its head does carry the fragment.
  private var head: some View {
    HStack(spacing: 6) {
      LeafIcon()
      if let label = GalleryScenarioDetailFormat.excerptHeadRoundLabel(
        excerpt, totalRounds: totalRounds) {
        Text(label)
          .textStyle(Typography.metaRound)
          .foregroundStyle(Color.mossDark)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
      recordedPill
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .overlay(alignment: .bottom) {
      // Mirrors `GameHeader`'s own hairline under the bar.
      Rectangle().fill(Color.ink.opacity(0.07)).frame(height: 1)
    }
  }

  /// Reads like `GameHeader`'s status pill, but is deliberately **not** a
  /// `GameHeaderStatus` case: that enum enumerates the states of a *run in
  /// progress*, and a curated excerpt is not a run state.
  ///
  /// The dot does not pulse. The whole claim of this section is that these
  /// lines really happened, so animating them into looking live would be the
  /// one dishonest pixel on the screen — the same call
  /// `ScenarioLanding.astro` made for the landing pages.
  ///
  /// Hidden from VoiceOver: the section's own heading already says this is a
  /// real run, so the pill would only add a decorative repetition.
  private var recordedPill: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(Color.mossDark)
        .frame(width: 5, height: 5)
      Text(String(localized: "Recorded"))
    }
    .textStyle(Typography.pillStatus)
    .foregroundStyle(Color.mossDark)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(Color.mossDark.opacity(0.14)))
    .accessibilityHidden(true)
  }

  private func stream(_ rows: [GalleryScenarioDetailFormat.ExcerptRow]) -> some View {
    VStack(spacing: ChatBubbleLayout.bubbleSpacing) {
      ForEach(rows) { row in
        if let dividerLabel = row.dividerLabel {
          PasturaStreamDivider {
            Text(dividerLabel)
              .textStyle(Typography.metaLabel)
              .foregroundStyle(Color.inkSecondary)
          }
        }
        AgentOutputRow(
          agent: row.entry.agent,
          // `statement` only — the Decision 1 allowlist, and the absence of
          // `inner_thought` is what keeps the row static (see the type doc).
          output: TurnOutput(fields: ["statement": row.entry.text]),
          phaseType: row.phaseType,
          showAllThoughts: false,
          agentPosition: row.agentPosition)
      }
    }
    .padding(12)
  }
}
