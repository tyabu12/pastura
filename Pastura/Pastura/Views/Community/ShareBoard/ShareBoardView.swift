import SwiftUI

/// Browse view for the curated gallery of scenarios (Share Board).
struct ShareBoardView: View {
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: ShareBoardViewModel?

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Share Board"))
    .task {
      let newViewModel = ShareBoardViewModel(
        galleryService: dependencies.galleryService,
        repository: dependencies.scenarioRepository)
      viewModel = newViewModel
      await newViewModel.load()
    }
  }

  @ViewBuilder
  private func content(viewModel: ShareBoardViewModel) -> some View {
    switch viewModel.state {
    case .idle, .loading:
      loadingView
    case .empty:
      emptyState(viewModel: viewModel)
    case .error(let message):
      errorState(message: message, viewModel: viewModel)
    case .loaded, .offlineWithCache:
      scenarioList(viewModel: viewModel)
    }
  }

  // MARK: - States

  private var loadingView: some View {
    ProgressView(String(localized: "Loading gallery…"))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func emptyState(viewModel: ShareBoardViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Gallery Unavailable"), systemImage: "wifi.slash")
    } description: {
      Text(
        String(
          localized: "Could not reach the Share Board and no cached content is available."))
    } actions: {
      Button(String(localized: "Retry")) {
        Task { await viewModel.refresh() }
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private func errorState(message: String, viewModel: ShareBoardViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button(String(localized: "Retry")) { Task { await viewModel.refresh() } }
    }
  }

  // MARK: - Scenario list

  @ViewBuilder
  private func scenarioList(viewModel: ShareBoardViewModel) -> some View {
    @Bindable var bindable = viewModel
    List {
      if case .offlineWithCache = viewModel.state {
        offlineBanner
      }
      Section {
        categoryPicker(selection: $bindable.selectedCategory)
      }
      Section {
        if viewModel.visibleScenarios.isEmpty {
          Text(String(localized: "No scenarios in this category."))
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.visibleScenarios, id: \.id) { scenario in
            NavigationLink(value: Route.galleryScenarioDetail(scenario: scenario)) {
              scenarioRow(scenario: scenario, viewModel: viewModel)
            }
            .accessibilityIdentifier("shareBoard.galleryCell.\(scenario.id)")
          }
        }
      } footer: {
        if let updated = viewModel.updatedAt {
          Text("Last updated: \(updated)")
        }
      }
    }
    .refreshable {
      await viewModel.refresh()
    }
  }

  private var offlineBanner: some View {
    Label(
      String(localized: "Offline — showing cached content"),
      systemImage: "wifi.exclamationmark"
    )
    .foregroundStyle(.secondary)
    .font(.footnote)
    .listRowBackground(Color.clear)
  }

  private func categoryPicker(selection: Binding<GalleryCategory?>) -> some View {
    Picker(String(localized: "Category"), selection: selection) {
      Text(String(localized: "All")).tag(GalleryCategory?.none)
      ForEach(GalleryCategory.allCases, id: \.self) { category in
        Text(category.displayName).tag(GalleryCategory?.some(category))
      }
    }
    .pickerStyle(.menu)
  }

  private func scenarioRow(
    scenario: GalleryScenario, viewModel: ShareBoardViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(scenario.title).font(.headline)
        Spacer()
        if viewModel.hasUpdate(for: scenario) {
          badge(text: String(localized: "Update"), style: .tint)
        } else if viewModel.isInstalled(scenario) {
          badge(text: String(localized: "Installed"), style: .secondary)
        }
      }
      Text(scenario.description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      HStack(spacing: 8) {
        Text(scenario.category.displayName)
        Text("·")
        Text("~\(scenario.estimatedInferences) inferences")
      }
      .font(.caption)
      .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }

  private enum BadgeStyle { case tint, secondary }

  private func badge(text: String, style: BadgeStyle) -> some View {
    Text(text)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        style == .tint
          ? Color.accentColor.opacity(0.2)
          : Color.secondary.opacity(0.15),
        in: Capsule()
      )
      .foregroundStyle(style == .tint ? Color.accentColor : .secondary)
  }
}

extension GalleryCategory {
  /// Human-readable display name for the UI picker.
  public var displayName: String {
    switch self {
    case .socialPsychology: return "Social Psychology"
    case .gameTheory: return "Game Theory"
    case .ethics: return "Ethics"
    case .roleplay: return "Roleplay"
    case .creative: return "Creative"
    case .experimental: return "Experimental"
    }
  }
}
