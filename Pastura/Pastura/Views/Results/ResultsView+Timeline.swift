import SwiftUI

/// Timeline rendering for the **aggregate** Past Results tab root — the
/// tab-identity redesign (PR1, #767) that distinguishes the History tab from
/// the Home / Search tabs, which share the same grouped-card list shape.
///
/// Date sections become a vertical **rail** with a node per day-header and per
/// row, read as a chronological log rather than yet another divided card list.
/// The row *content* (`simulationRow`: name + result pill + sheep + description
/// + relative timestamp) is reused verbatim from the grouped list — only the
/// section chrome (rail + nodes) is new. The familiar inline nav title is kept
/// (the timeline's identity comes from its rail/node shape, not a custom big
/// header), so the search field sits under the title as before. The pushed
/// per-scenario detail keeps the grouped list (it is a single section, not a
/// tab root).
///
/// Sibling-file extension on a Views/ (default-MainActor) type, so no
/// `nonisolated` annotation is needed (swift-isolation.md applies to
/// Models/LLM/Engine/Data). Layout constants live in ``ResultsTimelineMetrics``.
extension ResultsView {

  /// Aggregate-root timeline list: record count → date sections on a rail →
  /// load-more sentinel. Mirrors ``resultsList``'s ScrollView host (same
  /// `results.list` anchor the ScreenshotTour waits on). Neither carries the
  /// screen ground — it lives on the `body`'s container so the loading and
  /// empty arms get it too.
  func timelineList(viewModel: ResultsViewModel) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        recordCount(viewModel.totalRunCount)
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
    .accessibilityIdentifier("results.list")
  }

  /// Centered "N records" count under the (inline) nav title — restored from
  /// the pre-timeline header so the familiar subtitle sits below the title and
  /// above the first date section. Aggregate root only (`timelineList`).
  private func recordCount(_ count: Int) -> some View {
    // Plural-aware: the Int interpolation drives String-Catalog variant
    // selection (en `one`/`other`), so n=1 reads "1 record". Must be the
    // SwiftUI `Text("\(count)…")` form — the `String(localized: "…\(x)…")`
    // form is blocked by the `form_a_localized_interpolation` SwiftLint rule,
    // which can't tell an Int-plural count from a String-substitution hazard.
    // See .claude/rules/i18n-ui.md § "Plurals — the sanctioned exception to Form B". Key stays "%lld records".
    Text("\(count) records")
      .textStyle(Typography.metaValue)
      .foregroundStyle(Color.muted)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
      .padding(.top, ResultsTimelineMetrics.headerTopPadding)
      .accessibilityIdentifier("results.recordCount")
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
