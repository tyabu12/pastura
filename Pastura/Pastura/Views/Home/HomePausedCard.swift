import SwiftUI

/// The "resume" **hero** for the most-recent paused run — the editorial focal
/// element of the ホーム (Home) tab (tab-identity PR3, 案C 中庸; visual source
/// `docs/design/tab-identity/lookbook.html`). A moss-gradient card carrying an
/// eyebrow ("Interrupted Scenario") / scenario name / description / footer
/// (Round X/Y progress + a prominent Resume button). A nil `rounds` hides the
/// progress label (orphaned / name-only metadata). Geometry tokens live in
/// ``HomeHeroLayout``.
///
/// **P3 (#667)**: the Resume button pushes ``Route/resumeSimulation`` onto the
/// current tab's stack (the Home tab — `@Environment(AppRouter.self)` resolves
/// to the tab the card lives in, per `.claude/rules/navigation.md`).
struct HomePausedCard: View {
  let summary: PausedScenarioSummary
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppRouter.self) private var router

  /// Pure mapping from the card's summary to its resume destination, extracted
  /// so the dispatch is unit-testable without a live `AppRouter`. Identity is
  /// the paused run's id; the name rides along as an identity-neutral
  /// `RouteHint` for the nav title (ADR-008).
  static func resumeRoute(for summary: PausedScenarioSummary) -> Route {
    .resumeSimulation(simulationId: summary.runId, initialName: .init(summary.name))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: HomeHeroLayout.contentSpacing) {
        eyebrow
        Text(summary.name)
          // Hero title — larger/bolder than a list row so the resume card is
          // the screen's focal element. Semantic font (scales with Dynamic
          // Type); not a HomeHeroLayout token (SwiftUI.Font isn't Equatable).
          .font(.title3.weight(.bold))
          .foregroundStyle(Color.ink)
        if let description = summary.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(
              HomeScenarioRowFormat.descriptionLineLimit(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            )
            .truncationMode(.tail)
        }
      }
      footer
        .padding(.top, HomeHeroLayout.footerTopSpacing)
    }
    .padding(.horizontal, HomeHeroLayout.horizontalPadding)
    .padding(.vertical, HomeHeroLayout.verticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Inline 135° moss gradient — no new design token (reuses Color.moss at the
    // HomeHeroLayout opacity stops); the moss-soft hairline reads against the
    // cream screen background.
    .background(
      LinearGradient(
        colors: [
          Color.moss.opacity(HomeHeroLayout.gradientStartOpacity),
          Color.moss.opacity(HomeHeroLayout.gradientEndOpacity)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: HomeHeroLayout.cornerRadius, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: HomeHeroLayout.cornerRadius, style: .continuous)
        .strokeBorder(Color.mossSoft, lineWidth: HomeHeroLayout.borderWidth)
    )
    // The hero is an inset card (not full-bleed): it carries its own screen-edge
    // margin so it reads as the focal element above the compact list.
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    .accessibilityElement(children: .contain)
  }

  /// The eyebrow: a moss-dark status dot + the uppercase mono "Interrupted
  /// Scenario" label (reuses the existing catalog key — the muted section
  /// header that used to carry it on Home is dropped now that it lives here).
  ///
  /// The dot and the label take **different** tokens on purpose. The dot is a
  /// non-text shape, so it answers to WCAG's 3:1 bar and `mossDark` clears it;
  /// the label is 11pt text on the card's own moss gradient, where `mossDark`
  /// measured ≈3.92:1 against the 4.5:1 bar. Only the label moves to the
  /// `mossOnWash` role token, which reads ≈5.78:1 (#1327).
  private var eyebrow: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(Color.mossDark)
        .frame(width: HomeHeroLayout.eyebrowDotSize, height: HomeHeroLayout.eyebrowDotSize)
      Text(String(localized: "Interrupted Scenario"))
        .font(.system(size: HomeHeroLayout.eyebrowFontSize, weight: .semibold, design: .monospaced))
        .tracking(HomeHeroLayout.eyebrowTracking)
        .textCase(.uppercase)
        .foregroundStyle(Color.mossOnWash)
    }
  }

  private var footer: some View {
    HStack {
      if let progress = HomeScenarioRowFormat.pausedProgressLabel(
        currentRound: summary.currentRound, totalRounds: summary.rounds) {
        Text(progress)
          .font(.system(size: HomeHeroLayout.progressFontSize, design: .monospaced))
          // `mossInk` on this card's own moss wash. The ratio clears AA
          // (8.807 light / 5.927 dark, pinned by `mossInkWashSites`), but §2.3
          // assigns this token no role covering a round readout — so the
          // routing is unjustified rather than wrong. #1459, design-system §8's
          // closing ⚠️. The eyebrow above already moved to `mossOnWash` (#1327).
          .foregroundStyle(Color.mossInk)
      }
      Spacer()
      // Use the design-system primary style (mossDark + inkOnAccent label,
      // AA pass in light / AAA in dark — white only in light, a near-ground
      // tone in dark, ADR-028), NOT raw `.borderedProminent`: on iOS 26 the
      // latter opts into the Liquid Glass capsule, which renders the
      // `play.fill` glyph into the fill so it vanishes (design-system §5.8 /
      // PasturaPrimaryButtonStyle rationale). The explicit `inkOnAccent`
      // `foregroundStyle` on the label restores the icon.
      Button {
        router.push(Self.resumeRoute(for: summary))
      } label: {
        Label(String(localized: "Resume"), systemImage: "play.fill")
      }
      .buttonStyle(PasturaPrimaryButtonStyle(size: .compact))
      // Stable anchor so the ui-tour `09-home-resume` capture can wait for the
      // resume card to render before screenshotting.
      .accessibilityIdentifier("home.resumeButton")
    }
  }
}
