import SwiftUI

/// First-launch model picker. Shown when `AppState == .needsModelSelection`.
///
/// Gated by `ModelManager.shouldShowInitialModelPicker` — a returning user
/// with any persisted active id bypasses this screen entirely, as do
/// unsupported-device users (they fall through to the existing
/// `.needsModelDownload` unsupported UI).
///
/// ## Hosting
///
/// Rendered directly inside `RootView.mainContent` — **outside** the root
/// `NavigationStack`. Per `.claude/rules/navigation.md`, any view pushed
/// onto the root stack must not add its own `navigationDestination`;
/// this picker sidesteps the constraint by not being pushed at all.
///
/// ## Interaction
///
/// 1. Row tap → flips `selected` on `ModelSelectionState`. Visual only.
/// 2. Sticky CTA tap → `state.handleDownloadTap()`. Storage-OK path fires
///    `onSelect(selected)` immediately; low-storage path queues a
///    `StorageWarningSheet`, and the sheet's "Download anyway" then fires
///    `onSelect`. The caller (PasturaApp's `handleModelPick`) persists
///    the selection via `modelManager.setActiveModel(_:)`, calls
///    `startDownload`, and transitions `AppState` to `.needsModelDownload`.
///
/// ## Design system
///
/// Styled per `design_handoff_model_select/` (Claude Design hi-fi). Moss
/// accent for the CTA, Warm Gray ink for text, decimal-GB size shown
/// openly ("technology honesty" — we don't hide the ~3 GB download behind
/// euphemism). Quantization tag `(Q4_K_M)` is hidden on this screen per
/// the handoff directive — internal-identifier-only.
struct ModelPickerView: View {
  let modelManager: ModelManager
  let onSelect: (ModelID) -> Void

  @State private var state: ModelSelectionState
  @State private var hasAppeared = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  init(modelManager: ModelManager, onSelect: @escaping (ModelID) -> Void) {
    self.modelManager = modelManager
    self.onSelect = onSelect
    let recommended = ModelRegistry.recommendedModelID
    _state = State(
      initialValue: ModelSelectionState(
        selected: recommended,
        recommendedID: recommended,
        availableModels: modelManager.catalog
      )
    )
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      Color.screenBackground.ignoresSafeArea()
      mossHalo
      VStack(spacing: 0) {
        scrollContent
        stickyCTA
      }
    }
    .sheet(item: $state.pendingStorageWarning) { descriptor in
      StorageWarningSheet(
        descriptor: descriptor,
        onCancel: { state.cancelStorageWarning() },
        onProceed: {
          if let committed = state.acceptStorageWarning() {
            onSelect(committed.id)
          }
        }
      )
    }
    .task {
      // Seed the free-space probe once. The picker session is short
      // and downloads are gated by the CTA, so a single probe at
      // appearance is sufficient (vs. polling on every tap).
      state.availableStorageBytes = modelManager.availableStorageBytes()
      // Flip the first-paint animation gate. Each animated element
      // observes `hasAppeared` via its own `.animation(_, value:)`
      // modifier so the per-phase timing/delay applies independently.
      hasAppeared = true
    }
  }

  // MARK: - Scroll content

  private var scrollContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
          .padding(.horizontal, 24)
          .padding(.top, 60)
        horizon
          .padding(.horizontal, 24)
          .padding(.top, 32)
        listCard
          .padding(.horizontal, 18)
          .padding(.top, 24)
        Spacer(minLength: 24)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        LeafGlyph(size: 6)
        Text(String(localized: "PASTURA · SETUP"))
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .tracking(0.22 * 11)
          .foregroundStyle(Color.muted)
      }
      Text(String(localized: "Choose your first model"))
        .font(.system(size: 26, weight: .bold))
        .tracking(-0.015 * 26)
        .lineSpacing(26 * 0.3)
        .foregroundStyle(Color.mossInk)
        .padding(.top, 14)
      Text(String(localized: "Agents run entirely on your device."))
        .font(.system(size: 13.5))
        .lineSpacing(13.5 * 0.7)
        .foregroundStyle(Color.inkSecondary)
        .padding(.top, 14)
      Text(String(localized: "You can add another model later."))
        .font(.system(size: 13.5))
        .lineSpacing(13.5 * 0.7)
        .foregroundStyle(Color.muted)
    }
    .frame(maxWidth: 320, alignment: .leading)
    .opacity(hasAppeared ? 1 : 0)
    .offset(y: hasAppeared ? 0 : 14)
    .animation(entryAnimation(.header), value: hasAppeared)
  }

  // MARK: - Horizon

  private var horizon: some View {
    Horizon()
      .scaleEffect(x: hasAppeared ? 1 : 0.0001, y: 1, anchor: .center)
      .opacity(hasAppeared ? 1 : 0)
      .animation(entryAnimation(.horizon), value: hasAppeared)
  }

  // MARK: - List

  private var listCard: some View {
    VStack(spacing: 0) {
      ForEach(Array(state.availableModels.enumerated()), id: \.element.id) { index, descriptor in
        if index > 0 {
          Rectangle()
            .fill(Color.ink.opacity(0.08))
            .frame(height: 1)
        }
        ModelRow(
          descriptor: descriptor,
          isSelected: state.selected == descriptor.id,
          isRecommended: state.recommendedID == descriptor.id,
          onTap: { state.selected = descriptor.id }
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
        .blur(radius: hasAppeared ? 0 : 2)
        .animation(entryAnimation(.modelRow(index: index)), value: hasAppeared)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.bubbleBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.ink.opacity(0.10), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    // Soft "glow" approximation — SwiftUI shadow lacks `spread`, so the
    // handoff's `0 18px 36px -22px rgba(...)` is approximated as a
    // single softer shadow. Acceptable per the handoff "近似 OK" carve-out
    // for soft-glow-with-spread on iOS.
    .shadow(color: Color.moss.opacity(0.22), radius: 14, x: 0, y: 12)
    .accessibilityElement(children: .contain)
  }

  // MARK: - Sticky CTA

  private var stickyCTA: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(Color.ink.opacity(0.06))
        .frame(height: 1)
      Button(action: handleDownloadTap) {
        HStack(spacing: 10) {
          Text(ctaText)
            .font(.system(size: 16, weight: .semibold))
            .tracking(0.02 * 16)
          Text(sizeText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .opacity(0.55)
        }
        .foregroundStyle(Color.screenBackground)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.mossInk)
        )
        .shadow(color: Color.mossInk.opacity(0.45), radius: 8, x: 0, y: 6)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(ctaAccessibilityLabel)
      .accessibilityAddTraits(.isButton)
      .padding(.horizontal, 18)
      .padding(.top, 14)
      .padding(.bottom, 28)
    }
    .background {
      // `.ultraThinMaterial` honors Reduce Transparency automatically on
      // iOS 15+, but the explicit branch documents intent and matches
      // the handoff's "screen at 80% + frosted" spec under reduced mode.
      if reduceTransparency {
        Color.screenBackground
      } else {
        Rectangle().fill(.ultraThinMaterial)
      }
    }
  }

  // MARK: - Soft halo

  /// Soft moss halo behind the title area. Single light source — the
  /// "one allowed glow" per design-system §1.
  private var mossHalo: some View {
    GeometryReader { proxy in
      RadialGradient(
        gradient: Gradient(colors: [Color.moss.opacity(0.10), Color.clear]),
        center: .center,
        startRadius: 0,
        endRadius: proxy.size.width * 0.6
      )
      .offset(y: -proxy.size.height * 0.10)
      .ignoresSafeArea()
    }
    .accessibilityHidden(true)
  }

  // MARK: - CTA copy

  private var ctaText: String {
    guard let descriptor = state.selectedDescriptor else { return "" }
    let name = descriptor.shortDisplayName ?? descriptor.displayName
    return String(format: String(localized: "Download %@"), name)
  }

  private var sizeText: String {
    guard let descriptor = state.selectedDescriptor else { return "" }
    return ModelRow.formattedFileSize(descriptor.fileSize)
  }

  private var ctaAccessibilityLabel: String {
    guard let descriptor = state.selectedDescriptor else { return "" }
    let name = descriptor.shortDisplayName ?? descriptor.displayName
    return String(format: String(localized: "Download %@, %@"), name, sizeText)
  }

  // MARK: - Actions

  private func handleDownloadTap() {
    // `handleDownloadTap` returns true iff it queued a warning sheet;
    // in that case the sheet's "Download anyway" button fires `onSelect`.
    // Otherwise we commit immediately.
    if !state.handleDownloadTap() {
      onSelect(state.selected)
    }
  }

  // MARK: - Animation helpers

  /// Builds a `timingCurve(0.2, 0.7, 0.2, 1)` animation parameterized by
  /// `ModelSelectionAnimations.animationDuration` / `animationDelay`.
  /// Returns `nil` under reduceMotion so the View's `.animation(nil, value:)`
  /// applies no transition (instant snap to final state).
  private func entryAnimation(_ phase: ModelSelectionAnimations.Phase) -> Animation? {
    guard
      let duration = ModelSelectionAnimations.animationDuration(
        reduceMotion: reduceMotion, phase: phase)
    else {
      return nil
    }
    let delay =
      ModelSelectionAnimations.animationDelay(reduceMotion: reduceMotion, phase: phase) ?? 0
    return Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: duration).delay(delay)
  }
}

// MARK: - Previews

/// Builds a `ModelManager` suitable for preview hosting. Uses isolated
/// `UserDefaults` so previews don't pollute the simulator's domain.
@MainActor
private func previewManager(catalog: [ModelDescriptor] = ModelRegistry.catalog) -> ModelManager {
  let defaults = UserDefaults(suiteName: "ModelPickerPreview-\(UUID().uuidString)")!
  return ModelManager(
    physicalMemory: 8 * 1024 * 1024 * 1024,
    userDefaults: defaults,
    catalog: catalog
  )
}

#Preview("Gemma recommended") {
  ModelPickerView(
    modelManager: previewManager(),
    onSelect: { _ in }
  )
  .environment(DeepLinkGate())
}

#Preview("Qwen first in catalog") {
  // Inverting the catalog order surfaces the row-stagger animation with
  // Qwen at index 0. Recommendation is still Gemma per ModelRegistry.
  ModelPickerView(
    modelManager: previewManager(
      catalog: [ModelRegistry.qwen34B, ModelRegistry.gemma4E2B]),
    onSelect: { _ in }
  )
  .environment(DeepLinkGate())
}

#Preview("Low storage — warning destination") {
  // ModelManager.availableStorageBytes() can't be stubbed from preview
  // without a deeper seam; instead we present the warning sheet inline
  // so the preview shows the destination layout. Production presents
  // it conditionally via `.sheet(item:)`.
  StorageWarningSheet(
    descriptor: ModelRegistry.gemma4E2B,
    onCancel: {},
    onProceed: {}
  )
  .environment(DeepLinkGate())
}

// Reduce Motion visual parity is verified by:
//   1. Unit tests on `ModelSelectionAnimations` (all 4 phases → nil under
//      reduceMotion).
//   2. Manual QA: Settings > Accessibility > Reduce Motion → relaunch.
//
// Inline `.environment(\.accessibilityReduceMotion, true)` is not supported
// in Swift 6 strict mode (the keypath is read-only / Sendable-only), so a
// fourth preview targeting that env value is intentionally omitted.
