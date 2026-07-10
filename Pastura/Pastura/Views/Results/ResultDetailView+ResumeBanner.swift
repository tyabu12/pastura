import SwiftUI

extension ResultDetailView {
  /// ADR-021 D8 resume banner — shown at the top of the timeline for a
  /// `.failed` run that still holds a valid round checkpoint, offering a
  /// one-tap "resume from the next round". Mutually exclusive with the
  /// ``DegradedRunBadge`` annotation (that gates on `.completed`), so both can
  /// coexist in ``timelineLog`` without ever rendering together.
  ///
  /// Gated by ``FailedRunResumeBadge/isResumable(status:currentRound:)`` **and**
  /// a successful ``decodeState(from:)`` — defensive: `currentRound >= 1`
  /// implies a written checkpoint, but a corrupt `stateJSON` must not offer a
  /// resume that would immediately fail to seed. The push mirrors
  /// ``HomePausedCard`` (programmatic `router.push` of a helper-built
  /// `.resumeSimulation` route); the resume machinery is status-agnostic, so a
  /// `.failed` run resumes through the same path as a `.paused` one.
  ///
  /// Visual (moss-tinted card + primary Resume button) is code-review- and
  /// device-QA-gated per `.claude/rules/view-testing.md` rule 4; the show/hide
  /// and routing logic is unit-tested via ``FailedRunResumeBadge``.
  @ViewBuilder
  var resumeBanner: some View {
    if let sim = simulation,
      FailedRunResumeBadge.isResumable(
        status: sim.simulationStatus, currentRound: sim.currentRound),
      decodeState(from: sim) != nil {
      VStack(alignment: .leading, spacing: 10) {
        Label(
          String(localized: "This run stopped early"),
          systemImage: "exclamationmark.arrow.circlepath"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.ink)
        HStack {
          Spacer()
          Button {
            router.push(
              FailedRunResumeBadge.resumeRoute(
                simulationId: sim.id, name: sim.scenarioNameSnapshot))
          } label: {
            Label(
              String(
                format: String(localized: "Resume from round %lld"),
                FailedRunResumeBadge.resumeRoundLabel(currentRound: sim.currentRound)),
              systemImage: "play.fill")
          }
          .buttonStyle(PasturaPrimaryButtonStyle(size: .compact))
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Moss tint ties the banner to its Resume CTA (moss is the resume/paused
      // branding, cf. HomePausedCard) — muted opacity keeps it a top-of-timeline
      // annotation, not a focal hero.
      .background(
        Color.moss.opacity(0.08),
        in: RoundedRectangle(cornerRadius: PasturaCardMetrics.cornerRadius, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: PasturaCardMetrics.cornerRadius, style: .continuous)
          .strokeBorder(Color.mossSoft, lineWidth: 1)
      )
      .accessibilityIdentifier("resultDetail.resumeBanner")
    }
  }
}
