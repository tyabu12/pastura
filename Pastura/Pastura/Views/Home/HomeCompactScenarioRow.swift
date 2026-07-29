import SwiftUI

/// One compact row in the editorial Home scenario list (tab-identity PR3,
/// 案C 中庸; visual source `docs/design/tab-identity/lookbook.html`): a leading
/// icon tile, the scenario name, a `provenance · N agents · N rounds` caption,
/// and a trailing chevron. Lighter and denser than the shared summary row it
/// replaced on Home — that row was retired outright in #1296 once Search moved
/// to ``GalleryCatalogRow``. The icon is a single ``SheepAvatar`` for presets and
/// gallery-installed scenarios, or a document glyph for self-authored ones —
/// the sheep-vs-doc decision and the caption's provenance share one
/// classification (``HomeScenarioRowFormat/usesDocIcon(isPreset:category:)`` /
/// ``HomeScenarioRowFormat/provenanceCaption(isPreset:category:)``) so they
/// never disagree.
///
/// Wraps a value-based `NavigationLink` to the scenario detail; `initialName`
/// rides along as an identity-neutral ``RouteHint`` so the nav title shows from
/// the first frame without affecting Route identity (ADR-008,
/// `.claude/rules/navigation.md`). Geometry tokens live in
/// ``HomeCompactRowLayout``.
struct HomeCompactScenarioRow: View {
  let scenario: ScenarioRecord
  let metadata: ScenarioRowMetadata?
  var hasGalleryUpdate: Bool = false
  // Drives the description's line limit: one truncated line at normal sizes
  // (denser than the old 2-line Home row), unlimited wrap at accessibility
  // sizes so the text isn't clipped to nothing.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    NavigationLink(
      value: Route.scenarioDetail(
        scenarioId: scenario.id,
        initialName: .init(scenario.name)
      )
    ) {
      HStack(spacing: HomeCompactRowLayout.rowSpacing) {
        iconTile
        VStack(alignment: .leading, spacing: 2) {
          Text(scenario.name)
            // Name wraps rather than truncates — a clipped scenario title is
            // worse than a 2-line row in this dense layout.
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.ink)
          // One-line description restores the "what is this scenario?" context
          // the metadata-only caption can't carry — Home is where you pick what
          // to run, and preset names alone aren't self-explanatory.
          if let description = metadata?.description, !description.isEmpty {
            Text(description)
              .font(.footnote)
              .foregroundStyle(Color.inkSecondary)
              .lineLimit(
                HomeScenarioRowFormat.compactDescriptionLineLimit(
                  isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
              )
              .truncationMode(.tail)
          }
          caption
        }
        Spacer(minLength: 8)
        // Manual disclosure chevron — the ScrollView/`LazyVStack` host has no
        // List-cell chrome to supply one (matches the prior Home row).
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.muted)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, HomeCompactRowLayout.horizontalPadding)
      .padding(.vertical, HomeCompactRowLayout.verticalPadding)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("home.scenarioListCell.\(scenario.id)")
    // Preserve the gallery-update signal for VoiceOver now that the inline
    // "Update" text badge is gone (the visible dot on the tile is decorative).
    .accessibilityValue(hasGalleryUpdate ? Text(String(localized: "Update")) : Text(""))
  }

  /// The leading icon tile: a moss-wash rounded square framing either a sheep
  /// avatar (preset / gallery) or a document glyph (self-made). Decorative —
  /// the adjacent name `Text` carries the row's identity, so the tile is hidden
  /// from VoiceOver (mirrors ``SheepAvatar``'s own `.accessibilityHidden`).
  private var iconTile: some View {
    let shape = RoundedRectangle(
      cornerRadius: HomeCompactRowLayout.iconTileCornerRadius, style: .continuous)
    return ZStack {
      shape
        .fill(Color.moss.opacity(HomeCompactRowLayout.iconTileBackgroundOpacity))
        .overlay(
          shape.strokeBorder(
            Color.mossSoft, lineWidth: HomeCompactRowLayout.iconTileBorderWidth))
      if HomeScenarioRowFormat.usesDocIcon(
        isPreset: scenario.isPreset, category: scenario.category) {
        Image(systemName: "doc.text")
          .font(.system(size: HomeCompactRowLayout.docGlyphFontSize))
          .foregroundStyle(Color.mossDark)
      } else {
        SheepAvatar(
          character: .forAgent(scenario.name), size: HomeCompactRowLayout.sheepSize)
      }
    }
    .frame(width: HomeCompactRowLayout.iconTileSize, height: HomeCompactRowLayout.iconTileSize)
    .overlay(alignment: .topTrailing) {
      if hasGalleryUpdate {
        Circle()
          .fill(Color.moss)
          .frame(
            width: HomeCompactRowLayout.updateBadgeDotSize,
            height: HomeCompactRowLayout.updateBadgeDotSize
          )
          .overlay(
            Circle().strokeBorder(
              Color.screenBackground, lineWidth: HomeCompactRowLayout.updateBadgeDotStrokeWidth)
          )
          // Nudge so the dot straddles the tile's corner.
          .offset(x: 3, y: -3)
      }
    }
    .accessibilityHidden(true)
  }

  /// The `provenance · N agents · N rounds` caption. Segments are
  /// already-localized strings joined with a verbatim `·`, so `Text(verbatim:)`
  /// avoids re-interpreting them as `LocalizedStringKey` lookups.
  private var caption: some View {
    let segments = HomeScenarioRowFormat.compactCaptionSegments(
      isPreset: scenario.isPreset,
      category: scenario.category,
      agentCount: metadata?.agentCount,
      rounds: metadata?.rounds)
    return Text(verbatim: segments.joined(separator: " · "))
      .font(.system(size: HomeCompactRowLayout.captionFontSize, design: .monospaced))
      .tracking(HomeCompactRowLayout.captionTracking)
      .foregroundStyle(Color.muted)
      .lineLimit(1)
      .truncationMode(.tail)
  }
}
