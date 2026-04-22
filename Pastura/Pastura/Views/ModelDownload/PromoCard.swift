import Combine
import SwiftUI

/// Promotional card shown at the bottom of the demo replay screen while
/// the model downloads. Three responsibilities:
///
/// 1. DL progress (8 dots + percent + size + ETA) driven by `ModelState`.
/// 2. Rotating body copy (slots A → B → C → A …) driven by an independent
///    foreground-accumulated timer. Background time is excluded per
///    `demo-replay-ui.md` §PromoCard: "BG 復帰時の挙動: 位置継続".
/// 3. Inline retry affordance when `.error` arrives *after* replay has
///    started, per ADR-007 §3.3 (b) — the progress area swaps to an
///    error message + retry button while the body copy keeps rotating.
struct PromoCard: View {

  let modelState: ModelState
  let replayHadStarted: Bool
  let onRetry: () -> Void

  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var currentSlot: Int = 0
  @State private var foregroundElapsed: TimeInterval = 0
  @State private var lastForegroundAnchor: Date? = Date()
  @State private var downloadStartDate: Date?

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
        Text("もう一度試す")
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            RoundedRectangle(cornerRadius: Radius.button)
              .fill(Color.moss))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 7)
  }

  // MARK: - Body row (dog mark + rotating copy)

  private var bodyRow: some View {
    HStack(alignment: .top, spacing: 12) {
      DogMark(size: 26)
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
    if case .downloading = newState, downloadStartDate == nil {
      downloadStartDate = Date()
    }
  }

  private func computeEtaMinutes(progress: Double) -> Int? {
    guard let start = downloadStartDate, progress >= 0.01 else { return nil }
    let elapsed = Date().timeIntervalSince(start)
    let total = elapsed / progress
    let remaining = max(0, total - elapsed)
    return Int(remaining / 60)
  }

  // MARK: - Pure helpers (testable)

  /// Computes the next slot rotation state from the current accumulator,
  /// the last foreground anchor, and the current time. All inputs are
  /// explicit so the caller can unit-test wrap-around, BG pauses, and
  /// resume continuity without `@State` or a live clock.
  nonisolated static func computeSlotState(
    previousSlot: Int,
    foregroundElapsed: TimeInterval,
    lastAnchor: Date?,
    now: Date,
    slotDuration: TimeInterval
  ) -> SlotRotationState {
    let inflight = lastAnchor.map { now.timeIntervalSince($0) } ?? 0
    let totalInSlot = foregroundElapsed + inflight
    if totalInSlot >= slotDuration {
      // Slot advances; accumulator resets. The anchor only advances to `now`
      // when foregrounded (nil anchor means BG and stays nil).
      return SlotRotationState(
        slot: (previousSlot + 1) % 3,
        foregroundElapsed: 0,
        lastAnchor: lastAnchor == nil ? nil : now)
    }
    return SlotRotationState(
      slot: previousSlot,
      foregroundElapsed: foregroundElapsed,
      lastAnchor: lastAnchor)
  }

  /// Return value of ``computeSlotState(previousSlot:foregroundElapsed:lastAnchor:now:slotDuration:)``.
  ///
  /// Explicitly `nonisolated` so the pure rotation math is testable from a
  /// nonisolated test suite without hopping the main actor.
  nonisolated struct SlotRotationState: Equatable, Sendable {
    let slot: Int
    let foregroundElapsed: TimeInterval
    let lastAnchor: Date?
  }

  /// Slot copy (draft) from `docs/design/design-system.md` §7.
  /// Final wording is gated on the copy pass per spec §2 decision 13.
  static func slotCopy(_ slot: Int) -> String {
    switch slot % 3 {
    case 0: return "AIエージェントが、あなたのiPhoneの中で対話します"
    case 1: return "少しだけお待ちください。その間、他のエージェントたちの様子をどうぞ"
    default: return "このアプリは広告もログインもなく、あなたの端末だけで静かに動きます"
    }
  }

  /// `残り約N分` when minutes > 0, `まもなく` when <= 0, nil to hide.
  static func formatEta(minutes: Int?) -> String? {
    guard let minutes = minutes else { return nil }
    return minutes <= 0 ? "まもなく" : "残り約\(minutes)分"
  }
}

// MARK: - Previews

#Preview("Downloading 35%") {
  PromoCard(
    modelState: .downloading(progress: 0.35),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Downloading 95%") {
  PromoCard(
    modelState: .downloading(progress: 0.95),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}

#Preview("Error after start (retry)") {
  PromoCard(
    modelState: .error("ネットワーク接続が切れました"),
    replayHadStarted: true,
    onRetry: {}
  )
  .padding(.vertical, 40)
  .background(Color.screenBackground)
}
