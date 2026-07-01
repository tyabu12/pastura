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
  // Programmatic push for the overflow-menu Edit / Use-as-Template actions:
  // a `NavigationLink` inside a `Menu` does not reliably push, so these go
  // through the current tab's router (navigation.md § "When to use what").
  // Not `private`: the sibling-file `+Sections.swift` extension reads it
  // for the language-toggle `replaceTop` (private is file-scoped).
  @Environment(AppRouter.self) var router
  @State private var viewModel: ScenarioDetailViewModel?
  @State private var showDeleteConfirm = false

  /// Drives the content scroll position so a cross-language swap can reset
  /// to the top edge (see `scenarioContent`'s `.onChange`).
  @State private var scrollPosition = ScrollPosition()

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
      // Trailing actions: the primary Run CTA sits at the trailing edge —
      // the prime slot for the app's core action — with the low-frequency
      // `⋯` overflow menu (edit / clone / delete) to its LEFT. This reverses
      // the earlier layout that pinned Run as a bottom `.safeAreaInset`
      // button: the InFlightSimulationIndicator "return to run" pill is a
      // bottom-aligned `RootTabView` overlay shown while a run is
      // parked-away, so it collided with a bottom-pinned Run CTA here.
      // Moving Run into the toolbar frees the bottom edge for that pill.
      //
      // Two SEPARATE `ToolbarItem`s (not one HStack): a single `ToolbarItem`
      // renders only one control, so an HStack of {Menu, Button} drops the
      // Button entirely (verified — the Run button vanished from the a11y
      // tree). Declaration order `[⋯]` then `[Run]` places Run at the
      // trailing edge; the system's inter-item spacing separates the two so
      // a stray tap doesn't land on the ⋯ menu (which holds the destructive
      // Delete). They gate on independent optionals (`record` vs `scenario`).
      if let record = viewModel?.record {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            // Read-only sources (preset / installed gallery copy) get a
            // clone-as-template action; user scenarios get direct edit.
            if record.isPreset || (viewModel?.isGallerySourced ?? false) {
              Button {
                router.push(.editor(templateYAML: record.yamlDefinition))
              } label: {
                Label(String(localized: "Use as Template"), systemImage: "doc.on.doc")
              }
            } else {
              Button {
                router.push(.editor(editingId: scenarioId))
              } label: {
                Label(String(localized: "Edit"), systemImage: "pencil")
              }
            }
            // Delete is gated EXACTLY as the prior toolbar button (`!isPreset`),
            // so an installed gallery copy (`isPreset == false`) stays deletable
            // — gallery read-only blocks edit/overwrite, not deleting the copy.
            if !record.isPreset {
              Button(role: .destructive) {
                showDeleteConfirm = true
              } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityIdentifier("scenarioDetail.actionsMenu")
        }
        .hidingPasturaSharedBackground()
      }
      if let viewModel, let scenario = viewModel.scenario {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            // Synchronous tap → plain `push` onto the current tab's stack
            // (navigation.md § "When to use what"). A `NavigationLink` in a
            // toolbar has no precedent here and the file's `Menu`-push
            // caveat (see the `router` doc-comment above) argues against it.
            // `initialName` feeds SimulationView's nav title from the first
            // frame; identity-neutral via `RouteHint` (ADR-008).
            router.push(
              .simulation(
                scenarioId: scenarioId,
                initialName: .init(scenario.name)))
          } label: {
            Label(String(localized: "Run"), systemImage: "play.fill")
              // Toolbar `Label`s default to icon-only; force the "実行" text
              // to render beside the ▶ (the approved [▶ Run] treatment, not
              // an ambiguous icon-only button).
              .labelStyle(.titleAndIcon)
          }
          .buttonStyle(PasturaToolbarButtonStyle(variant: .primary))
          .disabled(!viewModel.canRun)
          // `PasturaToolbarButtonStyle` doesn't dim on `.disabled`, so the
          // not-runnable state is signalled explicitly (mirrors the old
          // bottom CTA's `.opacity(0.4)`).
          .opacity(viewModel.canRun ? 1 : 0.4)
          .accessibilityLabel(String(localized: "Run Simulation"))
          .accessibilityIdentifier("scenarioDetail.runSimulationButton")
        }
        .hidingPasturaSharedBackground()
      }
    }
    // `.alert` (not `.confirmationDialog`): iOS 26 renders a body-attached
    // confirmationDialog as a popover whose arrow anchors to the body
    // centre, not the triggering control. A centred alert avoids that.
    // Alerts don't auto-add a Cancel button, so it's added explicitly.
    .alert(
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
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
    // Keyed on `scenarioId` so the cross-language toggle reloads: tapping
    // "View in English/Japanese" calls `AppRouter.replaceTop`, which swaps
    // the top route in place — NavigationStack reuses this leaf by stack
    // position, so a plain `.task` (load-once) would keep the prior
    // language. `.task(id:)` re-fires when `scenarioId` changes; on first
    // appear it also runs once. Building the new VM fully before assigning
    // keeps the sections from popping in piecemeal — the gallery banner,
    // the cross-language affordance, and the scenario content stabilise
    // together (the old VM stays shown during the brief reload, no
    // ProgressView flash).
    .task(id: scenarioId) {
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
        summaryStrip(scenario: scenario, viewModel: viewModel)
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
    // can wait on it instead of sleeping. (The primary Run CTA now lives in
    // the toolbar, so the earlier "must precede `.safeAreaInset`" id-scoping
    // constraint no longer applies.)
    .accessibilityIdentifier("scenarioDetail.list")
    .scrollPosition($scrollPosition)
    // A cross-language toggle reuses this leaf (replaceTop swaps the top
    // route in place), so the ScrollView keeps its prior offset — which
    // would leave the new variant's large title above the fold. Reset to
    // the top *edge* (offset 0) so the swapped-in scenario reads from its
    // title and the `.large` nav title re-expands. `scrollTo(edge:)` lands
    // at true offset 0 — unlike `ScrollViewReader.scrollTo(_:anchor:.top)`,
    // which aligns the first item one title-height below 0 and collapses
    // the large title to inline (#830).
    .onChange(of: scenarioId) {
      scrollPosition.scrollTo(edge: .top)
    }
  }

}
