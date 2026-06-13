import SwiftUI

/// Displays scenario metadata, personas, phases, and a launch button.
struct ScenarioDetailView: View {
  let scenarioId: String
  /// Render-time hint for the navigation title — supplied by callers
  /// that already have the scenario name in memory (e.g., HomeView's
  /// list rows, GalleryScenarioDetailView post-install) so the title
  /// is correct from the first frame of the push, before the view
  /// model finishes loading. `nil` falls back to the empty-string
  /// placeholder. See ADR-008.
  var initialName: String?

  @Environment(AppDependencies.self) private var dependencies
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: ScenarioDetailViewModel?
  @State private var showDeleteConfirm = false

  var body: some View {
    Group {
      if let viewModel {
        if viewModel.isLoading {
          ProgressView(String(localized: "Loading..."))
        } else if let scenario = viewModel.scenario {
          scenarioContent(scenario: scenario, viewModel: viewModel)
        } else if let error = viewModel.errorMessage {
          ContentUnavailableView(
            String(localized: "Error"),
            systemImage: "exclamationmark.triangle",
            description: Text(error)
          )
        }
      } else {
        ProgressView()
      }
    }
    // 3-tier fallback (ADR-008): loaded scenario name (authoritative,
    // wins after VM load completes) → push-time `initialName` hint
    // (covers the ~30–80ms load window when callers supplied it) →
    // empty string (defensive default for callers that didn't supply
    // a hint; "Scenario" would be a misleading flash).
    .navigationTitle(viewModel?.scenario?.name ?? initialName ?? "")
    .navigationBarTitleDisplayMode(.large)
    // Hide the system back button to escape iOS 26's Liquid Glass capsule
    // styling on the chevron. `.navigationBarBackButtonHidden` ALSO
    // disables the `interactivePopGestureRecognizer` on iOS 26 (verified
    // by `BackGestureTests` — see PasturaBackButton's UIKit bridge for
    // why), so we pair it with `.preservesPasturaSwipeBackGesture()`
    // which mounts an invisible probe to reinstall the gesture.
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
      if let record = viewModel?.record, !record.isPreset {
        ToolbarItem(placement: .destructiveAction) {
          Button(String(localized: "Delete"), role: .destructive) {
            showDeleteConfirm = true
          }
          .buttonStyle(PasturaToolbarButtonStyle(variant: .destructive))
        }
        .hidingPasturaSharedBackground()
      }
    }
    .confirmationDialog(
      String(localized: "Delete Scenario?"),
      isPresented: $showDeleteConfirm
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        Task {
          if let viewModel, await viewModel.deleteScenario() {
            dismiss()
          }
        }
      }
    }
    .task {
      // Defer assignment until `load()`, `refreshGalleryStatus()`, and
      // `loadSibling()` all complete so the rendered sections don't
      // pop in piecemeal — the gallery banner, the cross-language
      // affordance, and the scenario content stabilise together.
      // Guard prevents re-creation under `.task` re-fire.
      guard viewModel == nil else { return }
      let newViewModel = ScenarioDetailViewModel(
        repository: dependencies.scenarioRepository)
      await newViewModel.load(scenarioId: scenarioId)
      await newViewModel.refreshGalleryStatus(using: dependencies.galleryService)
      await newViewModel.loadSibling()
      viewModel = newViewModel
    }
  }

  private func scenarioContent(
    scenario: Scenario,
    viewModel: ScenarioDetailViewModel
  ) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        galleryBannerSection(viewModel: viewModel)
        overviewSection(scenario: scenario, viewModel: viewModel)
        contextSection(scenario: scenario)
        personasSection(scenario: scenario)
        phasesSection(scenario: scenario)
        validationSection(viewModel: viewModel)
        actionsSection(scenario: scenario, viewModel: viewModel)
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    // Post-load anchor: this ScrollView only exists once the scenario
    // content has resolved, so ScreenshotTourTests / NavigationRegressionTests
    // can wait on it instead of sleeping.
    .accessibilityIdentifier("scenarioDetail.list")
  }

  // MARK: - Section scaffolding

  /// A muted section header laid above a ``PasturaCard``, mirroring the
  /// inset-grouped section structure the `List` used to provide. Pass a
  /// `nil` title for an unheadered card (banner / actions).
  @ViewBuilder
  private func cardSection<Content: View>(
    _ title: String?, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      if let title {
        Text(title)
          .font(.subheadline)
          .foregroundStyle(Color.muted)
          .padding(.leading, 6)
      }
      PasturaCard { content() }
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
  }

  private var rowDivider: some View {
    Divider().overlay(Color.rule)
  }

  private func infoRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(Color.ink)
      Spacer(minLength: 8)
      Text(value).foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 14)
  }

  // MARK: - Sections

  @ViewBuilder
  private func galleryBannerSection(viewModel: ScenarioDetailViewModel) -> some View {
    if viewModel.hasGalleryUpdate, let entry = viewModel.galleryScenario {
      cardSection(nil) {
        NavigationLink(value: Route.galleryScenarioDetail(scenario: entry)) {
          PasturaRowLabel(
            title: String(localized: "Update available from Shared Scenarios"),
            systemImage: "arrow.down.circle.fill")
        }
        .buttonStyle(.plain)
      }
    } else if viewModel.isGallerySourced {
      cardSection(nil) {
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

  private func overviewSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    cardSection(String(localized: "Overview")) {
      VStack(spacing: 0) {
        infoRow(String(localized: "Agents"), value: "\(scenario.agentCount)")
        rowDivider
        infoRow(String(localized: "Rounds"), value: "\(scenario.rounds)")
        rowDivider
        infoRow(
          String(localized: "Est. Inferences"),
          value: "\(viewModel.estimatedInferences)")
        if !scenario.description.isEmpty {
          rowDivider
          Text(scenario.description)
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
        }
      }
    }
  }

  private func contextSection(scenario: Scenario) -> some View {
    cardSection(String(localized: "Context")) {
      Text(scenario.context)
        .font(.subheadline)
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }
  }

  private func personasSection(scenario: Scenario) -> some View {
    cardSection(String(localized: "Personas (\(scenario.personas.count))")) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.personas.enumerated()), id: \.element.name) { index, persona in
          if index > 0 { rowDivider }
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

  private func phasesSection(scenario: Scenario) -> some View {
    cardSection(String(localized: "Phases (\(scenario.phases.count))")) {
      VStack(spacing: 0) {
        ForEach(Array(scenario.phases.enumerated()), id: \.offset) { index, phase in
          if index > 0 { rowDivider }
          HStack {
            Text("\(index + 1).")
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
  private func validationSection(viewModel: ScenarioDetailViewModel) -> some View {
    if let error = viewModel.validationError {
      cardSection(nil) {
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

  private func actionsSection(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    cardSection(nil) {
      VStack(spacing: 0) {
        // initialName supplies the scenario name to SimulationView's
        // navigationTitle from the first frame, before loadAndRun()
        // re-parses the YAML. Identity-neutral via RouteHint (ADR-008).
        NavigationLink(
          value: Route.simulation(
            scenarioId: scenarioId,
            initialName: .init(scenario.name)
          )
        ) {
          PasturaRowLabel(
            title: String(localized: "Run Simulation"), systemImage: "play.fill")
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canRun)
        .opacity(viewModel.canRun ? 1 : 0.4)
        .accessibilityIdentifier("scenarioDetail.runSimulationButton")

        rowDivider
        NavigationLink(value: Route.results(scenarioId: scenarioId)) {
          PasturaRowLabel(
            title: String(localized: "Past Results"),
            systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(.plain)

        siblingLanguageLink(scenario: scenario, viewModel: viewModel)

        if let record = viewModel.record {
          rowDivider
          if record.isPreset || viewModel.isGallerySourced {
            // Preset and gallery rows are read-only; offer a clone-as-template
            // action instead of direct edit so users can customize safely.
            NavigationLink(value: Route.editor(templateYAML: record.yamlDefinition)) {
              PasturaRowLabel(
                title: String(localized: "Use as Template"), systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
          } else {
            NavigationLink(value: Route.editor(editingId: scenarioId)) {
              PasturaRowLabel(title: String(localized: "Edit"), systemImage: "pencil")
            }
            .buttonStyle(.plain)
          }
        }
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
  private func siblingLanguageLink(
    scenario: Scenario, viewModel: ScenarioDetailViewModel
  ) -> some View {
    if let sibling = viewModel.siblingVariant {
      let label: String =
        scenario.language == "ja"
        ? String(localized: "View in English")
        : String(localized: "View in Japanese")
      rowDivider
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
