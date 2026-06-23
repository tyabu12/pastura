import SwiftUI

/// Timeline rendering for the **aggregate** Past Results tab root — the
/// tab-identity redesign (PR1, #767) that distinguishes the History tab from
/// the Home / Search tabs, which share the same grouped-card list shape.
///
/// Date sections become a vertical **rail** with a node per day-header and per
/// row, read as a chronological log rather than yet another divided card list.
/// The row *content* (`simulationRow`: name + result pill + sheep + description
/// + relative timestamp) is reused verbatim from the grouped list — only the
/// section chrome and the editorial screen header are new. The pushed
/// per-scenario detail keeps the grouped list (it is a single section, not a
/// tab root).
///
/// Sibling-file extension on a Views/ (default-MainActor) type, so no
/// `nonisolated` annotation is needed (swift-isolation.md applies to
/// Models/LLM/Engine/Data). Layout constants live in
/// ``ResultsTimelineMetrics``; the big-title `Font` is inline + code-review-
/// gated (not `Equatable`, so it cannot live in the change-detector enum).
extension ResultsView {

  /// Aggregate-root timeline list: editorial header → date sections on a rail →
  /// load-more sentinel. Mirrors ``resultsList``'s ScrollView host (same
  /// `results.list` anchor the ScreenshotTour waits on, same background).
  func timelineList(viewModel: ResultsViewModel) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        editorialHeader(count: viewModel.totalRunCount)
        ForEach(viewModel.sections) { section in
          daySection(section)
        }
        if viewModel.hasMore {
          loadMoreSentinel(viewModel: viewModel)
            .padding(.top, ResultsTimelineMetrics.daySectionTopSpacing)
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    .accessibilityIdentifier("results.list")
  }

  /// Editorial screen header — eyebrow + big title + record count. Replaces the
  /// nav-bar title (aggregate root sets it empty) so there is a single
  /// "Past Results" title (the in-scroll one), not two. The eyebrow is
  /// decorative (`.accessibilityHidden`) since the big title already announces
  /// "Past Results" — avoids VoiceOver reading "History, Past Results".
  private func editorialHeader(count: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "History"))
        // Eyebrow + big-title `Font`/`tracking` are inline + code-review-gated
        // (not `Equatable`, so they stay out of ``ResultsTimelineMetrics``).
        // Provisional sizes; final type scale tuned on-device.
        .font(.system(.caption2, design: .monospaced).weight(.semibold))
        .tracking(1.4)
        .textCase(.uppercase)
        .foregroundStyle(Color.mossDark)
        .accessibilityHidden(true)
      Text(String(localized: "Past Results"))
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(Color.ink)
        .padding(.top, ResultsTimelineMetrics.eyebrowTitleSpacing)
      Text(String(format: String(localized: "%lld records"), count))
        .textStyle(Typography.metaValue)
        .foregroundStyle(Color.muted)
        .padding(.top, ResultsTimelineMetrics.titleCountSpacing)
        .accessibilityIdentifier("results.recordCount")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    .padding(.top, ResultsTimelineMetrics.headerTopPadding)
    // Stacks with the first section's own `.padding(.top, daySectionTopSpacing)`
    // for a wider header-to-content gutter than the inter-section gap — don't
    // "deduplicate" this into one inset.
    .padding(.bottom, ResultsTimelineMetrics.daySectionTopSpacing)
  }

  /// One date section: a big day header + its rows, threaded by a continuous
  /// rail. The rail is a `.background` so it spans the whole section height
  /// (through the gaps between rows) rather than per-row segments that would
  /// break at `rowSpacing`.
  private func daySection(_ section: ResultsViewModel.ResultSection) -> some View {
    VStack(alignment: .leading, spacing: ResultsTimelineMetrics.rowSpacing) {
      dayHeader(section.title)
      ForEach(section.rows) { row in
        timelineRow(row)
      }
    }
    .background(alignment: .leading) {
      Rectangle()
        .fill(Color.mossSoft)
        .frame(width: ResultsTimelineMetrics.railWidth)
        .padding(
          .leading, ResultsTimelineMetrics.railLeadingInset - ResultsTimelineMetrics.railWidth / 2)
    }
    .padding(.leading, PasturaCardMetrics.horizontalMargin)
    .padding(.trailing, PasturaCardMetrics.horizontalMargin)
    .padding(.top, ResultsTimelineMetrics.daySectionTopSpacing)
  }

  /// Day-section header: an outlined node sitting on the rail + the localized
  /// date title (Today / This Week / "Month [Year]" — `section.title` is
  /// already resolved by ``ResultsRowFormat``).
  private func dayHeader(_ title: String) -> some View {
    HStack(spacing: ResultsTimelineMetrics.dayHeaderGap) {
      Circle()
        .strokeBorder(Color.moss, lineWidth: ResultsTimelineMetrics.dayNodeBorderWidth)
        .background(Circle().fill(Color.screenBackground))
        .frame(
          width: ResultsTimelineMetrics.dayNodeSize, height: ResultsTimelineMetrics.dayNodeSize
        )
        .frame(width: ResultsTimelineMetrics.railLeadingInset * 2, alignment: .center)
      Text(title)
        .font(.title3.weight(.bold))
        .foregroundStyle(Color.ink)
    }
  }

  /// One run on the rail: a node (rail punctuation) + a tappable card carrying
  /// the shared ``simulationRow`` content. The node color reuses the result
  /// pill's tint (single source — no parallel color map), so a future pill
  /// retint repaints the node in lockstep. The dot is at-a-glance only; the
  /// adjacent pill text carries the precise state (so failed vs running, both
  /// `.pending`/muted here, stay disambiguated by the label).
  private func timelineRow(_ row: ResultsViewModel.SimulationRow) -> some View {
    let item = row.item
    let pill = ResultsRowFormat.resultPill(
      status: item.simulationStatus, topScores: item.topScores,
      currentRound: item.currentRound, totalRounds: row.totalRounds)
    return HStack(alignment: .top, spacing: 0) {
      Circle()
        .fill(pillForeground(pill.style))
        .frame(
          width: ResultsTimelineMetrics.rowNodeSize, height: ResultsTimelineMetrics.rowNodeSize
        )
        .frame(width: ResultsTimelineMetrics.railLeadingInset * 2, alignment: .center)
        // Drop the node onto the card's title line rather than the card's top edge.
        .padding(.top, ResultsTimelineMetrics.rowVerticalPadding)
      NavigationLink(value: Route.resultDetail(simulationId: item.id)) {
        simulationRow(row)
          .padding(.vertical, ResultsTimelineMetrics.rowVerticalPadding)
          .padding(.horizontal, ResultsTimelineMetrics.rowHorizontalPadding)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.bubbleBackground, in: RoundedRectangle(cornerRadius: Radius.bubbleBody))
          .overlay(
            RoundedRectangle(cornerRadius: Radius.bubbleBody)
              .stroke(Color.rule, lineWidth: PasturaCardMetrics.borderWidth)
          )
          .shadow(
            color: PasturaShadows.tight.color.color, radius: PasturaShadows.tight.radius,
            x: PasturaShadows.tight.x, y: PasturaShadows.tight.y)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("results.row.\(item.id)")
      .padding(
        .leading, ResultsTimelineMetrics.rowIndent - ResultsTimelineMetrics.railLeadingInset * 2)
    }
  }
}
