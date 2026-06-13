import SwiftUI

/// Browse view for the curated gallery of scenarios (Shared Scenarios).
struct SharedScenariosListView: View {
  @Environment(AppDependencies.self) private var dependencies
  @State private var viewModel: SharedScenariosViewModel?

  var body: some View {
    Group {
      if let viewModel {
        content(viewModel: viewModel)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(String(localized: "Shared Scenarios"))
    .navigationBarBackButtonHidden(true)
    .preservesPasturaSwipeBackGesture()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        PasturaBackButton()
      }
      .hidingPasturaSharedBackground()
    }
    .task {
      let newViewModel = SharedScenariosViewModel(
        galleryService: dependencies.galleryService,
        repository: dependencies.scenarioRepository)
      viewModel = newViewModel
      await newViewModel.load()
    }
  }

  @ViewBuilder
  private func content(viewModel: SharedScenariosViewModel) -> some View {
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

  private func emptyState(viewModel: SharedScenariosViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Gallery Unavailable"), systemImage: "wifi.slash")
    } description: {
      Text(
        String(
          localized: "Could not reach Shared Scenarios and no cached content is available."))
    } actions: {
      Button(String(localized: "Retry")) {
        Task { await viewModel.refresh() }
      }
      .buttonStyle(PasturaPrimaryButtonStyle())
    }
  }

  private func errorState(message: String, viewModel: SharedScenariosViewModel) -> some View {
    ContentUnavailableView {
      Label(String(localized: "Error"), systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button(String(localized: "Retry")) { Task { await viewModel.refresh() } }
        .buttonStyle(PasturaPrimaryButtonStyle())
    }
  }

  // MARK: - Scenario list

  @ViewBuilder
  private func scenarioList(viewModel: SharedScenariosViewModel) -> some View {
    @Bindable var bindable = viewModel
    ScrollView {
      VStack(alignment: .leading, spacing: PasturaCardMetrics.interCardSpacing) {
        if case .offlineWithCache = viewModel.state {
          offlineBanner
        }
        PasturaSection {
          HStack {
            Text(String(localized: "Category")).foregroundStyle(Color.ink)
            Spacer(minLength: 8)
            categoryPicker(selection: $bindable.selectedCategory)
          }
          .padding(.horizontal, 17)
          .padding(.vertical, 8)
        }
        if viewModel.visibleScenarios.isEmpty {
          PasturaSection {
            Text(String(localized: "No scenarios in this category."))
              .foregroundStyle(Color.inkSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 17)
              .padding(.vertical, 14)
          }
        } else {
          PasturaSection {
            VStack(spacing: 0) {
              ForEach(Array(viewModel.visibleScenarios.enumerated()), id: \.element.id) {
                index, scenario in
                if index > 0 { PasturaRowDivider() }
                NavigationLink(value: Route.galleryScenarioDetail(scenario: scenario)) {
                  galleryRow(scenario: scenario, viewModel: viewModel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sharedScenarios.galleryCell.\(scenario.id)")
              }
            }
          }
        }
        if let updated = viewModel.updatedAt {
          Text(String(format: String(localized: "Last updated: %@"), updated))
            .font(.caption)
            .foregroundStyle(Color.muted)
            .padding(.leading, PasturaCardMetrics.horizontalMargin + 6)
        }
      }
      .padding(.vertical, PasturaCardMetrics.interCardSpacing)
    }
    .background(Color.screenBackground.ignoresSafeArea())
    .refreshable {
      await viewModel.refresh()
    }
  }

  private var offlineBanner: some View {
    HStack(spacing: 8) {
      Image(systemName: "wifi.exclamationmark")
        .foregroundStyle(Color.warning)
      Text(String(localized: "Offline — showing cached content"))
        .font(.footnote)
        .foregroundStyle(Color.inkSecondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
  }

  /// Wraps ``scenarioRow`` with a trailing chevron + full-row hit target,
  /// restoring the List disclosure affordance after the ScrollView move.
  private func galleryRow(
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    HStack(spacing: 10) {
      scenarioRow(scenario: scenario, viewModel: viewModel)
      Image(systemName: "chevron.forward")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
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
    scenario: GalleryScenario, viewModel: SharedScenariosViewModel
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(scenario.title).font(.headline).foregroundStyle(Color.ink)
        Spacer()
        if viewModel.hasUpdate(for: scenario) {
          badge(text: String(localized: "Update"), style: .tint)
        } else if viewModel.isInstalled(scenario) {
          badge(text: String(localized: "Installed"), style: .secondary)
        }
      }
      Text(scenario.description)
        .font(.subheadline)
        .foregroundStyle(Color.inkSecondary)
        .lineLimit(2)
      HStack(spacing: 8) {
        Text(scenario.category.displayName)
        Text("·")
        Text(
          String(format: String(localized: "~%lld inferences"), scenario.estimatedInferences))
      }
      .font(.caption)
      .foregroundStyle(Color.muted)
    }
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
    case .socialPsychology: return String(localized: "Social Psychology")
    case .gameTheory: return String(localized: "Game Theory")
    case .ethics: return String(localized: "Ethics")
    case .roleplay: return String(localized: "Roleplay")
    case .creative: return String(localized: "Creative")
    case .experimental: return String(localized: "Experimental")
    }
  }
}
