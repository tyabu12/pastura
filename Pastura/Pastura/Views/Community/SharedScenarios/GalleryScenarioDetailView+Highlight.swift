import SwiftUI

/// The curated-highlight section of `GalleryScenarioDetailView` (ADR-029),
/// split into a sibling extension to keep the host file inside SwiftLint's
/// length caps.
///
/// **Static text only.** ADR-029 Decision 6 keeps highlights outside the
/// Phase-3 "Replay gallery" deferral only while this section renders a fixed,
/// authored excerpt with no run / replay / seek affordance of any kind. The
/// edit invitation is copy, not a button — the screen's existing install CTA
/// is the only action.
///
/// Every string sourced from the highlight file is remote content (currently
/// Japanese, on both `en` and `ja` chrome) and must never resolve as a
/// `LocalizedStringKey`. The teaser and the YAML hook say so explicitly with
/// `Text(verbatim:)`. The excerpt lines reach ``AgentOutputRow`` instead, which
/// is safe for a different reason: it is handed `String` / `Substring`
/// *values*, and the `LocalizedStringKey` overload of `Text.init` binds only to
/// string literals, so a non-literal argument selects the `StringProtocol` one.
extension GalleryScenarioDetailView {

  /// Renders only once the loader has fetched **and** verified a highlight.
  /// Absent, in-flight, and every verification failure alike collapse to
  /// `EmptyView()` — no spinner, no placeholder, no error UI (ADR-029
  /// Decision 4: a failure the user cannot act on is worse than absence).
  @ViewBuilder
  var highlightSection: some View {
    if let highlight = highlightLoader?.highlight {
      PasturaSection(String(localized: "A glimpse of a real run")) {
        VStack(alignment: .leading, spacing: 16) {
          GalleryHighlightRunFigure(
            excerpt: highlight.excerpt, totalRounds: scenario.rounds)
          teaserLine(highlight.teaser)
          yamlHook(highlight.yamlHook)
          editInvitation
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// One spoiler-free line teasing the outcome — italic + secondary ink so it
  /// reads as a caption on the excerpt rather than another spoken line.
  fileprivate func teaserLine(_ teaser: String) -> some View {
    Text(verbatim: teaser)
      .font(.callout.italic())
      .foregroundStyle(Color.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The YAML that produced the excerpt, in a code-style block, plus its
  /// caption. Both strings are remote content.
  fileprivate func yamlHook(_ hook: GalleryHighlightYAMLHook) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(String(localized: "The YAML behind these lines"))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.ink)
      Text(verbatim: GalleryScenarioDetailFormat.yamlFragmentForDisplay(hook.fragment))
        // Text-style-relative so the code block scales with Dynamic Type
        // alongside the section's prose (a fixed point size would not).
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(Color.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
          Color.bubbleBackground,
          in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text(verbatim: hook.caption)
        .font(.footnote)
        .foregroundStyle(Color.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Open-in-app-and-edit invitation (ADR-029 Decision 5). Deliberately says
  /// nothing about submitting a scenario back to the gallery — user
  /// submissions are the Phase 3 marketplace — and adds no run affordance.
  fileprivate var editInvitation: some View {
    Text(
      String(
        localized:
          "Once it is on your device you can rewrite this YAML freely. Change the setup and see where your own run goes."
      )
    )
    .font(.caption)
    .foregroundStyle(Color.muted)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
