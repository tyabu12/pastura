import SwiftUI

/// Detail view for a single gallery scenario. Renders the scenario metadata
/// and the primary action button (`Try` / `Update` / `Open` depending on
/// local install state).
///
/// All deep navigation goes through `AppRouter`. Mixing
/// `navigationDestination(item:)` here previously caused a regression
/// where `Run Simulation` from the installed `ScenarioDetailView`
/// would re-render the gallery destination instead of advancing.
struct GalleryScenarioDetailView: View {
  let scenario: GalleryScenario

  // `dependencies` / `modelManager` / `isWorking` drop `private` so the
  // sibling extension in `GalleryScenarioDetailView+RecommendedModel.swift`
  // can read them. Same pattern as `.claude/rules/testing.md`'s sibling-file
  // extension guidance — `private` blocks cross-file extension access.
  @Environment(AppDependencies.self) var dependencies
  @Environment(AppRouter.self) private var router
  @Environment(ModelManager.self) var modelManager
  @Environment(\.lastDeepLinkedScenarioId) private var lastDeepLinkedScenarioId
  @State private var viewModel: SharedScenariosViewModel?
  @State var isWorking = false
  @State private var outcomeAlert: OutcomeAlert?
  @State private var isReportSheetPresented = false

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(scenario.title)
    // The scenario name is a proper-noun title, so it reads as a large
    // heading like ScenarioDetail — not the `.inline` it would otherwise
    // inherit from the `.inline` Search tab root (design-system § 5.11).
    .navigationBarTitleDisplayMode(.large)
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    .task {
      // Defer assignment until `load()` completes so the action button
      // never renders "Try this scenario" between VM creation and the
      // installed-snapshot refresh landing — already-installed users
      // would otherwise see "Try" briefly before it switches to "Update"
      // / "Open local copy". Guard prevents re-creation under `.task`
      // re-fire.
      guard viewModel == nil else { return }
      let newViewModel = SharedScenariosViewModel(
        galleryService: dependencies.galleryService,
        repository: dependencies.scenarioRepository)
      await newViewModel.load()
      viewModel = newViewModel
    }
    .alert(item: $outcomeAlert) { alert in
      Alert(title: Text(alert.title), message: Text(alert.message))
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
      ToolbarItem(placement: .primaryAction) {
        // Report is the only action, so surface it directly as an icon button
        // rather than nesting it under an ellipsis menu. `.iconOnly` keeps the
        // label text as the VoiceOver name.
        Button {
          isReportSheetPresented = true
        } label: {
          Label(
            String(localized: "Report this scenario"),
            systemImage: "exclamationmark.bubble")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(PasturaToolbarButtonStyle(variant: .secondary))
        .accessibilityIdentifier("galleryDetail.reportButton")
      }
      .hidingPasturaSharedBackground()
    }
    .reportSheet(isPresented: $isReportSheetPresented, context: .scenario(scenario))
  }

  private var wasOpenedFromDeepLink: Bool {
    lastDeepLinkedScenarioId == scenario.id
  }

  // MARK: - Content

  @ViewBuilder
  private func content(viewModel: SharedScenariosViewModel) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        if wasOpenedFromDeepLink { deepLinkBanner }
        headerCard
        whatHappensSection
        detailsCard
        recommendedModelSection
        actionFooter(viewModel: viewModel)
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
  }

  private var deepLinkBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "link")
        .foregroundStyle(Color.muted)
      Text(String(localized: "Opened from an external link"))
        .font(.footnote)
        .foregroundStyle(Color.inkSecondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
  }

  private var headerCard: some View {
    // The scenario title is already the `.large` navigation title, so the card
    // carries only the description — no duplicate heading above it.
    PasturaSection {
      Text(scenario.description)
        .font(.body)
        .foregroundStyle(Color.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
    }
  }

  /// Ordered detail rows. Agents / Rounds / Language are omitted entirely when
  /// their backing value is absent (older-feed forward-compat), mirroring the
  /// "never fabricate unknown data" posture of `GalleryCatalogRowFormat`.
  private var detailRows: [(label: String, value: String)] {
    var rows: [(label: String, value: String)] = [
      (String(localized: "Category"), scenario.category.displayName)
    ]
    if let agentCount = scenario.agentCount {
      rows.append((String(localized: "Agents"), "\(agentCount)"))
    }
    if let rounds = scenario.rounds {
      rows.append((String(localized: "Rounds"), "\(rounds)"))
    }
    rows.append(
      (
        String(localized: "Recommended model"),
        ModelRegistry.lookup(id: scenario.recommendedModel)?.displayName
          ?? String(format: String(localized: "Unknown model (%@)"), scenario.recommendedModel)
      ))
    rows.append((String(localized: "Est. inferences"), "\(scenario.estimatedInferences)"))
    if let language = GalleryScenarioDetailFormat.languageLabel(code: scenario.language) {
      rows.append((String(localized: "Language"), language))
    }
    rows.append((String(localized: "Author"), scenario.author))
    rows.append((String(localized: "Added"), scenario.addedAt))
    return rows
  }

  private var detailsCard: some View {
    PasturaSection(String(localized: "Details")) {
      VStack(spacing: 0) {
        ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
          if index > 0 { PasturaRowDivider() }
          detailRow(row.label, value: row.value)
        }
      }
    }
  }

  /// "What happens" — the scenario's phase sequence as a numbered vertical
  /// step list (number + glyph + label per row). Hidden when no phases map
  /// (absent, empty, or all-unknown kinds).
  @ViewBuilder
  private var whatHappensSection: some View {
    let steps = GalleryScenarioDetailFormat.phaseSteps(phases: scenario.phases)
    if !steps.isEmpty {
      PasturaSection(String(localized: "What happens")) {
        VStack(spacing: 0) {
          // `enumerated().offset` id (mirroring `detailsCard`) keeps rows
          // stable when a scenario repeats a phase kind (e.g. two speak_each).
          ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            if index > 0 { PasturaRowDivider() }
            phaseStepRow(number: index + 1, symbol: step.symbol, label: step.label)
          }
        }
      }
    }
  }

  /// One "What happens" step: 1-based number + phase glyph + localized label.
  private func phaseStepRow(number: Int, symbol: String, label: String) -> some View {
    HStack(spacing: 12) {
      Text(number, format: .number)
        .foregroundStyle(Color.muted)
        .monospacedDigit()
        .frame(minWidth: 16, alignment: .trailing)
      // Decorative: the adjacent label carries the phase identity, so the
      // glyph is hidden from VoiceOver to avoid announcing the raw symbol name.
      Image(systemName: symbol)
        .foregroundStyle(Color.mossDark)
        .frame(width: 22, alignment: .center)
        .accessibilityHidden(true)
      Text(verbatim: label)
        .foregroundStyle(Color.ink)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 14)
  }

  private func actionFooter(viewModel: SharedScenariosViewModel) -> some View {
    VStack(spacing: 10) {
      actionButton(viewModel: viewModel)
      Text(
        String(
          localized:
            "Gallery scenarios are read-only — local edits are not permitted. Updates replace the stored YAML."
        )
      )
      .font(.caption)
      .foregroundStyle(Color.muted)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
  }

  private func detailRow(_ label: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(Color.ink)
      Spacer(minLength: 12)
      Text(value)
        .foregroundStyle(Color.muted)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 14)
  }

  private func actionButton(viewModel: SharedScenariosViewModel) -> some View {
    let installed = viewModel.isInstalled(scenario)
    let hasUpdate = viewModel.hasUpdate(for: scenario)
    let title: String
    if !installed {
      title = String(localized: "Try this scenario")
    } else if hasUpdate {
      title = String(localized: "Update")
    } else {
      title = String(localized: "Open local copy")
    }

    return Button {
      Task { await tap(viewModel: viewModel, installed: installed, hasUpdate: hasUpdate) }
    } label: {
      HStack {
        if isWorking { ProgressView() }
        Text(title)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(PasturaPrimaryButtonStyle())
    .disabled(isWorking)
    .accessibilityIdentifier("galleryDetail.tryButton")
  }

  // MARK: - Actions

  private func tap(
    viewModel: SharedScenariosViewModel, installed: Bool, hasUpdate: Bool
  ) async {
    if installed && !hasUpdate {
      // Already up to date — no install needed; jump straight to the
      // local copy via the same router pattern as the post-install path.
      pushToInstalled(scenarioId: scenario.id)
      return
    }
    isWorking = true
    defer { isWorking = false }
    let outcome = await viewModel.tryInstall(scenario)
    handle(outcome)
  }

  private func handle(_ outcome: SharedScenariosViewModel.TryOutcome) {
    switch outcome {
    case .installed(let id), .updated(let id):
      // The navigating outcomes push to the local copy instead of alerting.
      pushToInstalled(scenarioId: id)
    case .conflict, .hashMismatch, .networkError, .updateRequired:
      // The alerting outcomes map to copy via the pure Format helper (testable,
      // ADR-009). Exhaustive (no `default:`) so a future TryOutcome case forces
      // a decision here, not a silent mis-route.
      outcomeAlert = GalleryScenarioDetailFormat.installAlert(for: outcome)
    }
  }

  /// Push only when this view is still on top of the path. Guards against
  /// pushing onto an unrelated screen if the user popped back during the
  /// async install.
  ///
  /// `initialName` is sourced from the gallery curation `scenario.title`
  /// rather than the freshly-saved local `ScenarioRecord.name`. The
  /// `gallery.title == yaml.name` invariant is enforced by
  /// `GallerySeedYAMLTests` so the two values match at install time;
  /// if the invariant is ever violated, the title would briefly show the
  /// gallery curation string before snapping to the YAML name on load.
  private func pushToInstalled(scenarioId: String) {
    router.pushIfOnTop(
      expected: .galleryScenarioDetail(scenario: scenario),
      next: .scenarioDetail(
        scenarioId: scenarioId,
        initialName: .init(scenario.title)
      ))
  }
}

/// Alert content for a non-navigating install outcome. Internal (not
/// `private`) so ``GalleryScenarioDetailFormat/installAlert(for:)`` can build
/// it and its copy is unit-testable (ADR-009).
struct OutcomeAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
