import Combine
import SwiftUI

/// Promotional card shown at the bottom of the demo replay screen while
/// the model downloads. Four responsibilities:
///
/// 1. DL progress (8 dots + percent + size + ETA) driven by `ModelState`.
/// 2. Rotating body copy (slots A → B → C → A …) driven by an independent
///    foreground-accumulated timer. Background time is excluded per
///    `demo-replay-ui.md` §PromoCard: "BG 復帰時の挙動: 位置継続".
/// 3. Inline retry affordance when `.error` arrives *after* replay has
///    started, per ADR-007 §3.3 (b) — the progress area swaps to an
///    error message + retry button while the body copy keeps rotating.
/// 4. Optional inline Cancel: when `onCancel` is non-nil, a small `X`
///    sits on the trailing edge of the progress / retry row. The card
///    is the natural home for it because the action targets the DL
///    that the card is rendering — colocating destructive intent with
///    its target. The host owns the confirmation dialog.
struct PromoCard: View {

  let modelState: ModelState
  let replayHadStarted: Bool
  let onRetry: () -> Void
  /// When set, renders a small `X` button at the trailing edge of the
  /// progress / retry row. When `nil`, no cancel affordance is shown
  /// (first-launch DL is uncancellable per the slot's contract).
  let onCancel: (() -> Void)?

  init(
    modelState: ModelState,
    replayHadStarted: Bool,
    onRetry: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.modelState = modelState
    self.replayHadStarted = replayHadStarted
    self.onRetry = onRetry
    self.onCancel = onCancel
  }

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var currentSlot: Int = 0
  @State private var foregroundElapsed: TimeInterval = 0
  @State private var lastForegroundAnchor: Date? = Date()
  /// ETA anchor — re-set on every `non-.downloading → .downloading` transition
  /// so a retry after an error doesn't reuse the original session's start time.
  /// `downloadStartProgress` snapshots the progress at anchor time so the ETA
  /// formula works correctly when resuming from a non-zero offset.
  @State private var downloadStartDate: Date?
  @State private var downloadStartProgress: Double = 0

  /// Provisional 20 s / slot; the spec marks this as "暫定値" to be tuned
  /// during the copy pass.
  private static let slotDuration: TimeInterval = 20

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      metaRow
      bodyRow
    }
    .background(cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: Radius.promo))
    .overlay(alignment: .leading) { leftAccent }
    .overlay {
      RoundedRectangle(cornerRadius: Radius.promo)
        .strokeBorder(Color.promoBorder, lineWidth: 1)
    }
    .shadow(
      color: PasturaShadows.tight.color.color,
      radius: PasturaShadows.tight.radius,
      x: PasturaShadows.tight.x, y: PasturaShadows.tight.y
    )
    .shadow(
      color: PasturaShadows.soft.color.color,
      radius: PasturaShadows.soft.radius,
      x: PasturaShadows.soft.x, y: PasturaShadows.soft.y
    )
    .padding(.horizontal, 14)
    .padding(.bottom, 22)
    .onReceive(
      // `.common` mode is paused by iOS while the app is backgrounded, which
      // naturally aligns with the spec's foreground-only rotation policy.
      Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    ) { now in
      tick(now: now)
    }
    .onChange(of: scenePhase) { _, newPhase in
      handleScenePhase(newPhase)
    }
    .onChange(of: modelState, initial: true) { _, newState in
      handleModelStateChange(newState)
    }
  }

  // MARK: - Meta row (DL progress OR inline retry)

  @ViewBuilder
  private var metaRow: some View {
    if case .error(let message) = modelState, replayHadStarted {
      retryView(message: message)
    } else if case .downloading(let progress) = modelState {
      progressView(progress: progress)
    } else {
      // Not expected under the host's `fallbackBranch` — render empty
      // to keep the card height stable if this ever flickers.
      Color.clear.frame(height: 0)
    }
  }

  @ViewBuilder
  private func progressView(progress: Double) -> some View {
    let pct = Int(progress * 100)
    let dotsLit = Int((progress * 8).rounded())
    let downloadedGB = progress * 3.0
    let etaMinutes = computeEtaMinutes(progress: progress)

    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text("DL")
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.metaBaseL3)

        HStack(spacing: 2.5) {
          ForEach(0..<8, id: \.self) { idx in
            Circle()
              .fill(idx < dotsLit ? Color.metaDotOnL3 : Color.moss.opacity(0.38))
              .frame(width: 4, height: 4)
              // 600 ms cubic-bezier(.4,0,.2,1) per spec §animation. Dot light-up
              // is a state indicator, not decorative motion — kept even under
              // `reduceMotion` per PR plan.
              .animation(
                .timingCurve(0.4, 0, 0.2, 1, duration: 0.6),
                value: dotsLit)
          }
        }

        Text("\(pct)%")
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)

        Text("·")
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3.opacity(0.6))

        Text(String(format: "%.1f GB / 3.0 GB", downloadedGB))
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)

        Spacer(minLength: 0)

        if let onCancel {
          cancelButton(action: onCancel)
        }
      }

      if pct < 100, let etaText = Self.formatEta(minutes: etaMinutes) {
        Text(etaText)
          .textStyle(Typography.metaEta)
          .foregroundStyle(Color.metaStrongL3)
          .padding(.leading, 2)
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 7)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.updatesFrequently)
  }

  /// Trailing-edge "キャンセル" button for the progress / retry row.
  /// Neutral styling — `inkSecondary` text + `rule` 1pt border + clear
  /// fill — per `design-system.md` §2.6 "Cancel ボタンは赤くしない".
  /// The pastoral voice rejects red here; `danger` is reserved for
  /// the destructive-confirmation primary button instead.
  ///
  /// Tap target meets the HIG floor by stretching the button frame
  /// past the visible bordered chip via padding + `contentShape`,
  /// so the surrounding content area registers taps without inflating
  /// the visible chrome.
  private func cancelButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(String(localized: "キャンセル"))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay {
          RoundedRectangle(cornerRadius: Radius.button)
            .strokeBorder(Color.rule, lineWidth: 1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(String(localized: "Cancel download"))
  }

  @ViewBuilder
  private func retryView(message: String) -> some View {
    HStack(alignment: .center, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: 2) {
        Text("ダウンロードが中断しました")
          .textStyle(Typography.metaEta)
          .foregroundStyle(Color.metaStrongL3)
        Text(message)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      Button(action: onRetry) {
        Text("リトライ")
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            RoundedRectangle(cornerRadius: Radius.button)
              .fill(Color.moss))
      }
      .buttonStyle(.plain)
      if let onCancel {
        cancelButton(action: onCancel)
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 7)
  }

  // MARK: - Body row (dog mark + rotating copy)

  private var bodyRow: some View {
    HStack(alignment: .top, spacing: 12) {
      DogMark(size: Self.dogSize)
        // `DogMark`'s Canvas viewBox has ~5/26 of empty space above the
        // ear tip, so a raw `.top` alignment places the visible dog
        // below the text's first-line top. Shift the alignment anchor
        // to the dog's visible top — the scale-aware inset lives on
        // `DogMark` itself so this stays correct if `dogSize` changes.
        .alignmentGuide(.top) { _ in DogMark.visibleTopInset(forSize: Self.dogSize) }
      Text(Self.slotCopy(currentSlot))
        .textStyle(Typography.bodyPromo)
        .foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
        .id(currentSlot)  // forces cross-fade on slot change
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.top, 11)
    .padding(.bottom, 13)
    .animation(
      // 400 ms ease-in-out cross-fade; instant under `reduceMotion`.
      reduceMotion ? nil : .easeInOut(duration: 0.4),
      value: currentSlot)
  }

  /// Point size of the dog mark in the promo body row. Spec §PromoCard
  /// body structure (`demo-replay-ui.md` §PromoCard) pins this at 26 pt.
  ///
  /// `nonisolated` because it is read inside a `.alignmentGuide(.top)`
  /// `@Sendable` closure (line 182); pure value, safe to publish across
  /// isolation domains.
  nonisolated private static let dogSize: CGFloat = 26

  // MARK: - Decorative layers

  private var cardBackground: some View {
    RoundedRectangle(cornerRadius: Radius.promo)
      .fill(Color.promoBackground)
  }

  private var leftAccent: some View {
    Rectangle()
      .fill(Color.moss)
      .frame(width: 3)
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: Radius.promo,
          bottomLeadingRadius: Radius.promo))
  }

  // MARK: - Behavior

  private func tick(now: Date) {
    let next = Self.computeSlotState(
      previousSlot: currentSlot,
      foregroundElapsed: foregroundElapsed,
      lastAnchor: lastForegroundAnchor,
      now: now,
      slotDuration: Self.slotDuration)
    if next.slot != currentSlot {
      currentSlot = next.slot
    }
    foregroundElapsed = next.foregroundElapsed
    lastForegroundAnchor = next.lastAnchor
  }

  private func handleScenePhase(_ phase: ScenePhase) {
    let now = Date()
    switch phase {
    case .background, .inactive:
      if let anchor = lastForegroundAnchor {
        foregroundElapsed += now.timeIntervalSince(anchor)
      }
      lastForegroundAnchor = nil
    case .active:
      if lastForegroundAnchor == nil {
        lastForegroundAnchor = now
      }
    @unknown default:
      break
    }
  }

  private func handleModelStateChange(_ newState: ModelState) {
    // Symmetric anchor management:
    //   - any `.downloading` arrival with no prior anchor sets one (handles
    //     initial entry on view appear, fresh DL start, and retry after error)
    //   - any non-`.downloading` arrival resets the anchor (so the next
    //     `.downloading` re-anchors to the retry's start time, not the original
    //     attempt's)
    // `downloadStartProgress` snapshots the progress at anchor time so the
    // delta-progress ETA formula works when resuming from `.download` partial
    // bytes (initial progress > 0).
    if case .downloading(let progress) = newState {
      if downloadStartDate == nil {
        downloadStartDate = Date()
        downloadStartProgress = progress
      }
    } else {
      downloadStartDate = nil
      downloadStartProgress = 0
    }
  }

  private func computeEtaMinutes(progress: Double) -> Int? {
    guard let start = downloadStartDate else { return nil }
    let elapsed = Date().timeIntervalSince(start)
    guard
      let seconds = Self.computeEtaSeconds(
        currentProgress: progress,
        startProgress: downloadStartProgress,
        elapsed: elapsed)
    else { return nil }
    return seconds / 60
  }

}

// Pure helpers (`computeSlotState`, `computeEtaSeconds`, `slotCopy`, `formatEta`)
// live in `PromoCard+Helpers.swift`. `#Preview` blocks live in `PromoCard+Previews.swift`.
// Both splits keep this file under swiftlint's 400-line cap.
