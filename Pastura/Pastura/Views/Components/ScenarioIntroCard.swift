import SwiftUI

/// Opening "curtain" card shown above the live simulation log (issue #853).
///
/// The simulation screen otherwise drops straight into the first `ASSIGN` /
/// agent utterance with no scene-setting, which reads as disorienting on a
/// first run. This card presents the scenario premise once, at the top of the
/// chat stream, before the first agent turn — so the viewer knows *what this
/// place is* before the curtain rises.
///
/// Presentation-only by design (ADR-009): it takes already-resolved
/// ``Model`` strings, never the Engine/Data domain types, so both the live
/// simulation (fed from `Scenario.description`) and — in a follow-up — the
/// demo-replay screen (fed from the replay YAML `metadata.description`) can
/// share it without a Views-layer dependency creeping into either source.
///
/// The card is **static and side-effect-free** (no `onAppear` / `task`): it
/// sits inside the log's `LazyVStack`, so any lifecycle work would fire
/// unpredictably as it scrolls off. All data is passed in.
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

  var body: some View {
    PasturaCard {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        eyebrow
        if let title = model.title {
          Text(title)
            .textStyle(Typography.titlePhase)
            .foregroundStyle(Color.ink)
        }
        Text(model.premise)
          .textStyle(Typography.bodyBubble)
          .foregroundStyle(Color.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(Spacing.m)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    // Combine into one VoiceOver element so the premise is read as a single
    // "scene setting" announcement rather than icon + label + body fragments.
    .accessibilityElement(children: .combine)
  }

  /// Small "The premise" heading with a leading theatre-masks glyph — orients
  /// the viewer that this block is the scene setup, not an agent speaking.
  private var eyebrow: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: "theatermasks")
      Text(String(localized: "The premise"))
    }
    .textStyle(Typography.captionName)
    .foregroundStyle(Color.moss)
  }
}

#Preview("Scenario intro card") {
  ScrollView {
    VStack(spacing: 12) {
      if let model = ScenarioIntroCard.Model(
        title: nil,
        premise: "5人の参加者に「お題」が配られるが、1人だけ違うお題を持つ少数派（ウルフ）。会話から少数派を見抜き、投票で当てるゲーム。") {
        ScenarioIntroCard(model: model)
      }
      if let model = ScenarioIntroCard.Model(
        title: "Prisoner's Dilemma",
        premise: "Five players choose to cooperate or betray in a round-robin of adjacent pairings."
      ) {
        ScenarioIntroCard(model: model)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 8)
  }
  .background(Color.screenBackground)
}
