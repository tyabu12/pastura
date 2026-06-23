import SwiftUI

// Section builders for ScenarioDetailView, split into a sibling-file
// extension to keep the main view under SwiftLint type_body_length.
extension ScenarioDetailView {
  // MARK: - Sections

  @ViewBuilder
  func galleryBannerSection(viewModel: ScenarioDetailViewModel) -> some View {
    if viewModel.hasGalleryUpdate, let entry = viewModel.galleryScenario {
      PasturaSection {
        NavigationLink(value: Route.galleryScenarioDetail(scenario: entry)) {
          PasturaRowLabel(
            title: String(localized: "Update available from Shared Scenarios"),
            systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.plain)
      }
    } else if viewModel.isGallerySourced {
      PasturaSection {
        HStack(spacing: 10) {
          Image(systemName: "square.and.arrow.down.fill")
            .foregroundStyle(Color.moss)
          Text(String(localized: "From Shared Scenarios (read-only)"))
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
      }
    }
  }

  /// Compact one-line stat summary shown directly under the title — replaces
  /// the old labeled "Overview" card. Reuses the existing localized stat
  /// labels (`Agents` / `Rounds` / `Est. Inferences`) verbatim via the pure
  /// `ScenarioSummaryStrip.text` formatter (no new catalog keys, no plural). The
  /// leading inset matches the grouped-section header convention so the strip
  /// lines up with the section labels below it.
  func summaryStrip(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(
        ScenarioSummaryStrip.text(stats: [
          (String(localized: "Agents"), scenario.agentCount),
          (String(localized: "Rounds"), scenario.rounds),
          (String(localized: "Est. Inferences"), viewModel.estimatedInferences)
        ])
      )
      .font(.subheadline)
      .foregroundStyle(Color.inkSecondary)
      // Carry forward the empty-description guard so a scenario without a
      // description renders no stray line.
      if !scenario.description.isEmpty {
        Text(scenario.description)
          .font(.subheadline)
          .foregroundStyle(Color.muted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, PasturaCardMetrics.horizontalMargin + 6)
    .padding(.trailing, PasturaCardMetrics.horizontalMargin)
  }

  func contextSection(scenario: Scenario) -> some View {
    PasturaSection(String(localized: "Context")) {
      Text(scenario.context)
        .font(.subheadline)
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }
  }

  func personasSection(scenario: Scenario) -> some View {
    PasturaSection(
      String(format: String(localized: "Personas (%lld)"), scenario.personas.count)
    ) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.personas.enumerated()), id: \.element.name) { index, persona in
          if index > 0 { PasturaRowDivider() }
          VStack(alignment: .leading, spacing: 4) {
            Text(persona.name)
              .font(.headline)
              .foregroundStyle(Color.ink)
            Text(persona.description)
              .font(.caption)
              .foregroundStyle(Color.inkSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 17)
          .padding(.vertical, 12)
        }
      }
    }
  }

  func phasesSection(scenario: Scenario) -> some View {
    PasturaSection(
      String(format: String(localized: "Phases (%lld)"), scenario.phases.count)
    ) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.phases.enumerated()), id: \.offset) { index, phase in
          if index > 0 { PasturaRowDivider() }
          HStack {
            Text(verbatim: "\(index + 1).")
              .foregroundStyle(Color.muted)
              .monospacedDigit()
            Text(phase.type.rawValue)
              .font(.subheadline.monospaced())
              .foregroundStyle(Color.ink)
            if phase.type.requiresLLM {
              // `info` here is a quiet category badge for LLM-required phases, not a
              // notification — see design-system §2.6 for the alert-family scope.
              Image(systemName: "brain")
                .font(.caption)
                .foregroundStyle(Color.info)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 17)
          .padding(.vertical, 13)
        }
      }
    }
  }

  @ViewBuilder
  func validationSection(viewModel: ScenarioDetailViewModel) -> some View {
    if let error = viewModel.validationError {
      PasturaSection {
        HStack(spacing: 8) {
          Image(systemName: "xmark.circle.fill")
          Text(error)
          Spacer(minLength: 0)
        }
        .foregroundStyle(Color.dangerInk)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
      }
    }
  }

  func actionsSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    PasturaSection {
      VStack(spacing: 0) {
        // Run Simulation is the bottom-pinned primary CTA (see
        // ScenarioDetailView.runSimulationCTA); this section holds the
        // secondary affordances. Past Results is the first row, so no
        // leading divider.
        NavigationLink(value: Route.results(scenarioId: scenarioId)) {
          PasturaRowLabel(
            title: String(localized: "Past Results"),
            systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(.plain)

        siblingLanguageLink(scenario: scenario, viewModel: viewModel)
        // Edit / Use-as-Template moved to the `⋯` overflow menu in the
        // navigation bar (see ScenarioDetailView's toolbar).
      }
    }
  }

  /// Cross-language affordance per ADR-010 D6 — surfaces the sibling
  /// variant when one exists (Step D ships sibling pairs for the 4
  /// bundled presets). Hidden when no sibling is loaded.
  ///
  /// Label is the *destination* language name, resolved in the UI
  /// locale: "View in English" / "View in Japanese". Step D only
  /// ships ja↔en pairs — when a future language ships, the
  /// `default` arm becomes a generic fallback.
  @ViewBuilder
  func siblingLanguageLink(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    if let sibling = viewModel.siblingVariant {
      let label: String =
        scenario.language == "ja"
        ? String(localized: "View in English")
        : String(localized: "View in Japanese")
      PasturaRowDivider()
      NavigationLink(
        value: Route.scenarioDetail(
          scenarioId: sibling.id,
          initialName: .init(sibling.name)
        )
      ) {
        PasturaRowLabel(title: label, systemImage: "globe")
      }
      .buttonStyle(.plain)
    }
  }
}
