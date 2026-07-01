import SwiftUI

/// Opening "curtain" card shown above the live simulation log (issue #853).
///
/// The simulation screen otherwise drops straight into the first `ASSIGN` /
/// agent utterance with no scene-setting, which reads as disorienting on a
/// first run. This card presents the scenario premise once, at the top of the
/// chat stream, before the first agent turn — so the viewer knows *what this
/// place is* before the curtain rises. The premise types in at the playback
/// speed (the reveal *is* the scene-setting beat), matching the log's
/// typewriter feel.
///
/// Presentation-only by design (ADR-009): it takes already-resolved
/// ``Model`` strings, never the Engine/Data domain types, so both the live
/// simulation (fed from `Scenario.description`) and — in a follow-up — the
/// demo-replay screen (fed from the replay YAML `metadata.description`) can
/// share it without a Views-layer dependency creeping into either source.
struct ScenarioIntroCard: View {
  /// Resolved, display-ready values for the opening card.
  ///
  /// The failable initializer is the load-bearing visibility guard: an empty
  /// or whitespace-only premise yields `nil` so the caller renders nothing
  /// (mirroring `ScenarioSummaryRow`'s `!description.isEmpty` guard), rather
  /// than an empty card box above the log.
  nonisolated struct Model {
    /// Scenario name. Optional because the live simulation already shows the
    /// name in its header — it passes `nil` to avoid a redundant restatement,
    /// while the future demo adapter may pass it.
    let title: String?
    /// Viewer-facing premise (`Scenario.description` / replay
    /// `metadata.description`). Guaranteed non-empty once the model exists.
    let premise: String

    /// Builds a model, or returns `nil` when `premise` has no visible
    /// content. The emptiness check trims whitespace, but the stored
    /// ``premise`` is preserved verbatim (demo descriptions carry stray
    /// internal spaces from line-wrapping that must not be mutated).
    init?(title: String?, premise: String) {
      guard !premise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      self.title = title
      self.premise = premise
    }
  }

  let model: Model

  /// Typewriter speed for the premise reveal, in characters/second. `nil`
  /// renders the full premise at once (no animation) — the caller passes `nil`
  /// once the premise has already been revealed (type-once) and at
  /// `.instant` playback speed. Reduce Motion also forces the static path.
  var charsPerSecond: Double?

  /// Called once when the reveal animation *begins* (not on completion), so the
  /// caller can flip a type-once latch and pass `charsPerSecond == nil` on any
  /// later re-mount (the card lives in a `LazyVStack` and would otherwise
  /// re-type when the user scrolls back to the top). Fired at the start — not
  /// the end — so a reveal *interrupted* by an early unmount (the `.task` is
  /// cancelled mid-loop) still latches; the re-mounted card then renders the
  /// full premise statically instead of restarting the typewriter. Not called
  /// on the static path (nothing to latch — that path already shows full text).
  var onRevealStarted: (() -> Void)?

  /// Called once when the premise is fully shown — the end of the typewriter on
  /// the animated path, or immediately on the static path (instant speed /
  /// Reduce Motion / an already-latched re-mount). The live simulation uses
  /// this to gate the start of the conversation on the reveal finishing (#853).
  /// NOT called when the reveal is cancelled mid-typing (early unmount) — the
  /// run's own cancellation path releases its gate in that case.
  var onRevealComplete: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Number of leading premise characters currently revealed. Drives the
  /// typewriter; the full string is always laid out (hidden tail) so the card
  /// height never grows mid-reveal.
  @State private var visibleChars: Int = 0

  private var shouldType: Bool {
    guard let cps = charsPerSecond, cps > 0, !reduceMotion else { return false }
    return true
  }

  var body: some View {
    PasturaCard {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        eyebrow
        if let title = model.title {
          Text(title)
            .textStyle(Typography.titlePhase)
            .foregroundStyle(Color.ink)
        }
        premiseText
      }
      .padding(Spacing.m)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    // Combine into one VoiceOver element so the premise is read as a single
    // "scene setting" announcement. The concatenated Text below always holds
    // the full string (the unrevealed tail is only visually `.clear`), so
    // VoiceOver announces the whole premise regardless of the reveal state.
    .accessibilityElement(children: .combine)
    .task {
      guard shouldType else {
        // Static path (instant / Reduce Motion / already-latched re-mount):
        // full text at once, and the reveal is "complete" immediately.
        visibleChars = model.premise.count
        onRevealComplete?()
        return
      }
      await revealPremise()
    }
  }

  /// The premise text with a typewriter reveal. Rendered as
  /// `Text(visible) + Text(hidden).foregroundStyle(.clear)` so the full string
  /// is laid out from the first frame — line-wrap positions stay put and the
  /// card height is stable as characters appear (same idiom as
  /// `AgentOutputRow`'s replay path).
  private var premiseText: some View {
    let premise = model.premise
    let clamped = min(max(visibleChars, 0), premise.count)
    let splitIdx = premise.index(premise.startIndex, offsetBy: clamped)
    let visible = premise[..<splitIdx]
    let hidden = premise[splitIdx...]
    return (Text(visible) + Text(hidden).foregroundStyle(.clear))
      .textStyle(Typography.bodyBubble)
      .foregroundStyle(Color.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
      // Freeze the implicit text-change animation so revealed glyphs don't
      // cross-fade as the counter advances (matches AgentOutputRow).
      .animation(nil, value: clamped)
  }

  /// Small "The premise" heading with a leading scroll glyph — orients the
  /// viewer that this block is the scene setup / synopsis, not an agent
  /// speaking.
  private var eyebrow: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: "scroll")
        .accessibilityHidden(true)
      Text(String(localized: "The premise"))
    }
    .textStyle(Typography.captionName)
    .foregroundStyle(Color.moss)
  }

  /// Advances ``visibleChars`` from 0 to the full length at ``charsPerSecond``.
  /// Signals ``onRevealStarted`` up front (so the latch holds even if the loop
  /// is cancelled mid-reveal), then ``onRevealComplete`` once the full string is
  /// shown. Cancelled cleanly when the card leaves the hierarchy (the `.task`
  /// lifetime) — the cancel path fires neither completion.
  private func revealPremise() async {
    let total = model.premise.count
    visibleChars = 0
    guard let cps = charsPerSecond, cps > 0 else {
      visibleChars = total
      return
    }
    // Latch before typing: an early unmount cancels the loop below, but the run
    // has already had its intro beat — a re-mount should show full text, not
    // restart the typewriter.
    onRevealStarted?()
    while visibleChars < total {
      try? await Task.sleep(for: .seconds(1.0 / cps))
      // Cancelled mid-reveal (early unmount): do NOT signal completion — the
      // run's own cancellation path releases its intro gate.
      if Task.isCancelled { return }
      visibleChars += 1
    }
    onRevealComplete?()
  }
}

#Preview("Scenario intro card") {
  ScrollView {
    VStack(spacing: 12) {
      if let model = ScenarioIntroCard.Model(
        title: nil,
        premise: "5人の参加者に「お題」が配られるが、1人だけ違うお題を持つ少数派（ウルフ）。会話から少数派を見抜き、投票で当てるゲーム。") {
        ScenarioIntroCard(model: model, charsPerSecond: 10)
      }
      if let model = ScenarioIntroCard.Model(
        title: "Prisoner's Dilemma",
        premise: "Five players choose to cooperate or betray in a round-robin of adjacent pairings."
      ) {
        ScenarioIntroCard(model: model, charsPerSecond: nil)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
  }
  .background(Color.screenBackground)
}
