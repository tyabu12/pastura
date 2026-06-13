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
        Menu {
          Button {
            isReportSheetPresented = true
          } label: {
            Label(
              String(localized: "Report this scenario"),
              systemImage: "exclamationmark.bubble")
          }
          .accessibilityIdentifier("galleryDetail.reportMenuItem")
        } label: {
          Label(String(localized: "More"), systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(PasturaToolbarButtonStyle(variant: .secondary))
      }
      .hidingPasturaSharedBackground()
    }
    .sheet(isPresented: $isReportSheetPresented) {
      ReportScenarioSheet(context: .scenario(scenario))
        .deepLinkGated()
    }
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
    PasturaSection {
      VStack(alignment: .leading, spacing: 8) {
        Text(scenario.title)
          .font(.title2.bold())
          .foregroundStyle(Color.ink)
        Text(scenario.description)
          .font(.body)
          .foregroundStyle(Color.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(17)
    }
  }

  private var detailsCard: some View {
    PasturaSection(String(localized: "Details")) {
      VStack(spacing: 0) {
        detailRow(String(localized: "Category"), value: scenario.category.displayName)
        PasturaRowDivider()
        detailRow(String(localized: "Author"), value: scenario.author)
        PasturaRowDivider()
        detailRow(
          String(localized: "Recommended model"),
          value: ModelRegistry.lookup(id: scenario.recommendedModel)?.displayName
            ?? String(
              format: String(localized: "Unknown model (%@)"), scenario.recommendedModel))
        PasturaRowDivider()
        detailRow(
          String(localized: "Est. inferences"), value: "\(scenario.estimatedInferences)")
        PasturaRowDivider()
        detailRow(String(localized: "Added"), value: scenario.addedAt)
      }
    }
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
      pushToInstalled(scenarioId: id)
    case .conflict(let existingName, _):
      outcomeAlert = OutcomeAlert(
        title: String(localized: "Cannot install"),
        message: String(
          format: String(
            localized:
              "A scenario named “%@” already uses this id. Delete or rename it first, then try again."
          ),
          existingName))
    case .hashMismatch:
      outcomeAlert = OutcomeAlert(
        title: String(localized: "Integrity check failed"),
        message: String(
          localized:
            "The downloaded scenario does not match its expected signature. The gallery may have been updated. Pull to refresh and try again."
        ))
    case .networkError(let description):
      // description is a runtime error string from the network layer — not wrapped
      outcomeAlert = OutcomeAlert(title: String(localized: "Download failed"), message: description)
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

private struct OutcomeAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
