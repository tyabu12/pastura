import SwiftUI

// Pure, state-independent row-layout helpers for `ResultDetailView`, split
// into a sibling extension to keep the main file under swiftlint's 400-line
// `file_length` cap. These read no `@State` — only design tokens — so, unlike
// the export / load helpers, the split needs no `private`-visibility widening
// on the host.
extension ResultDetailView {

  /// Wraps a row with a leading indent and "↳ sub-phase" caption when the
  /// item's `phasePath` depth is greater than 1 (i.e. it lives inside a
  /// conditional branch). Top-level items (depth ≤ 1) pass through unchanged.
  @ViewBuilder
  func subPhaseWrapper<Content: View>(
    item: ResultDetailTimelineBuilder.Item,
    @ViewBuilder content: () -> Content
  ) -> some View {
    if (item.phasePath?.count ?? 0) > 1 {
      VStack(alignment: .leading, spacing: 2) {
        // `metaLabel` (9pt semibold mono, mixed case) — `tagPhase`
        // would force "↳ SUB-PHASE" UPPER which reads shouty for a
        // prose-like marker. tagPhase stays for one-word phase tags
        // (WORD WOLF). See design-system §3.2.
        Text(String(localized: "↳ sub-phase"))
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.muted)
          .padding(.leading, 32)
        content()
          .padding(.leading, 16)
      }
    } else {
      content()
    }
  }

  func roundSeparator(_ round: Int) -> some View {
    HStack {
      Rectangle().fill(Color.rule).frame(height: 1)
      // `metaLabel` keeps "Round N" mixed case — tagPhase would
      // upper-case to "ROUND N" which reads shouty for a prose
      // marker. tagPhase stays reserved for one-word phase tags
      // (WORD WOLF). See design-system §3.2.
      Text(String(format: String(localized: "Round %lld"), round))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      Rectangle().fill(Color.rule).frame(height: 1)
    }
    .padding(.vertical, 4)
  }
}
