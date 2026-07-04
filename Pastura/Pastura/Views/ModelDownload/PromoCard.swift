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
/// 4. Optional Cancel: when `onCancel` is non-nil, a full-width "Stop
///    download" link sits at the card's bottom edge. The card is the
///    natural home for it because the action targets the DL that the
///    card is rendering. Its own fixed-geometry row (not the
///    per-progress-rebuilt meta row) keeps the tap target stable — the
///    former trailing chip could drop a first tap under that churn. The
///    host owns the confirmation dialog.
struct PromoCard: View {

  let modelState: ModelState
  let replayHadStarted: Bool
  /// Total file size of the model being downloaded, in bytes. Drives both
  /// the `downloadedGB = progress * totalGB` calculation and the `/ X.X GB`
  /// denominator. Sourced from `ModelDescriptor.fileSize` by the host.
  /// Non-defaulted so production callsites must thread the active
  /// descriptor — previously the file hardcoded `3.0` GB, which under-
  /// or over-reported for any non-Gemma model.
  let totalBytes: Int64
  let onRetry: () -> Void
  /// When set, renders a full-width "Stop download" link at the card's
  /// bottom edge. When `nil`, no cancel affordance is shown
  /// (first-launch DL is uncancellable per the slot's contract).
  let onCancel: (() -> Void)?

  init(
    modelState: ModelState,
    replayHadStarted: Bool,
    totalBytes: Int64,
    onRetry: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
  ) {
    self.modelState = modelState
    self.replayHadStarted = replayHadStarted
    self.totalBytes = totalBytes
    self.onRetry = onRetry
    self.onCancel = onCancel
  }

  /// Total size in decimal GB (bytes / 1e9), matching the CLAUDE.md
  /// tech-stack table convention. Decimal not binary because the catalog
  /// figures are stated as `~2.5–3.1 GB each` (decimal).
  private var totalGB: Double { Double(totalBytes) / 1_000_000_000 }

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
      if let onCancel {
        cancelLinkRow(action: onCancel)
      }
    }
    .background(cardBackground)
    // `leftAccent` is overlaid BEFORE the clip so the card's rounded corner
    // trims the 3pt bar's top/bottom to follow the curve. Overlaying after
    // the clip (the prior form) left the bar unclipped, and its own
    // `UnevenRoundedRectangle(radius: Radius.promo)` self-clip can't round
    // inside a 3pt-wide frame — so the square ends poked past the corners.
    .overlay(alignment: .leading) { leftAccent }
    .clipShape(RoundedRectangle(cornerRadius: Radius.promo))
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
    let downloadedGB = progress * totalGB
    let etaMinutes = computeEtaMinutes(progress: progress)

    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(String(localized: "DL"))
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

        Text(verbatim: "\(pct)%")
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)

        Text("·")
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3.opacity(0.6))

        Text(String(format: String(localized: "%.1f GB / %.1f GB"), downloadedGB, totalGB))
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

  /// Full-width "Stop download" link at the card's bottom edge, shown only
  /// when `onCancel` is set. Replaces the former trailing-edge chip: living
  /// in its own fixed-geometry row — not the meta row that rebuilds on every
  /// progress update — keeps the hit region stable, and the full-width target
  /// is easier to hit. Neutral styling (`inkSecondary` text, `rule` hairline
  /// divider, no fill) per `design-system.md` §2.6 "Cancel ボタンは赤くしない";
  /// the visible text is self-describing, so no separate accessibility label.
  private func cancelLinkRow(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(String(localized: "Stop download"))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
          Rectangle()
            .fill(Color.rule)
            .frame(height: 1)
        }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func retryView(message: String) -> some View {
    HStack(alignment: .center, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "Download interrupted"))
          .textStyle(Typography.metaEta)
          .foregroundStyle(Color.metaStrongL3)
        Text(message)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      Button(action: onRetry) {
        Text(String(localized: "Retry"))
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
    // Plain full-height 3pt bar — the card's `.clipShape` (applied after this
    // overlay in `body`) rounds its ends to the corner curve. No self-clip.
    Rectangle()
      .fill(Color.moss)
      .frame(width: 3)
  }

  // MARK: - Behavior

  private func tick(now: Date) {
    let next = Self.computeSlotState(
      previousSlot: currentSlot,
      foregroundElapsed: foregroundElapsed,
      lastAnchor: lastForegroundAnchor,
      now: now,
      slotDuration: Self.slotDuration)
    // Guard every write: `computeSlotState` returns `foregroundElapsed` /
    // `lastAnchor` UNCHANGED on non-slot-advancing ticks (19 of every 20 —
    // the accumulation rides on the live `now − anchor` inflight term, not on
    // growing `foregroundElapsed`). A `@State` write invalidates `body` even
    // when the value is equal, so writing these unconditionally re-rendered
    // the whole card every second — churn that could drop the first tap on a
    // control living in the re-laid-out subtree. Assign only on real change.
    if next.slot != currentSlot {
      currentSlot = next.slot
    }
    if next.foregroundElapsed != foregroundElapsed {
      foregroundElapsed = next.foregroundElapsed
    }
    if next.lastAnchor != lastForegroundAnchor {
      lastForegroundAnchor = next.lastAnchor
    }
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

}

// MARK: - ETA anchor behavior
//
// Lifted to a same-file extension so the bookkeeping can be unit-test-shaped
// (delegate decisions to `nonisolated static` pure helpers) without inflating
// the main struct body past swiftlint's `type_body_length` cap.
extension PromoCard {

  fileprivate func handleModelStateChange(_ newState: ModelState) {
    // Anchor lifecycle (full rationale in `isResumeJump` doc comment):
    //   1. non-`.downloading` clears the anchor.
    //   2. first `.downloading` after a clear sets the anchor.
    //   3. resume-burst jump re-anchors so URLSession's cumulative-bytes
    //      report doesn't poison the throughput estimate.
    guard case .downloading(let progress) = newState else {
      downloadStartDate = nil
      downloadStartProgress = 0
      return
    }
    let shouldAnchor: Bool
    if let anchor = downloadStartDate {
      shouldAnchor = Self.isResumeJump(
        newProgress: progress,
        anchorProgress: downloadStartProgress,
        elapsedSinceAnchor: Date().timeIntervalSince(anchor))
    } else {
      shouldAnchor = true
    }
    if shouldAnchor {
      downloadStartDate = Date()
      downloadStartProgress = progress
    }
  }

  fileprivate func computeEtaMinutes(progress: Double) -> Int? {
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

// Pure helpers (`computeSlotState`, `computeEtaSeconds`, `isResumeJump`,
// `slotCopy`, `formatEta`) live in `PromoCard+Helpers.swift`. `#Preview` blocks
// live in `PromoCard+Previews.swift`. Both splits keep this file under
// swiftlint's 400-line cap.
