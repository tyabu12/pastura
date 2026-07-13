import SwiftUI

extension ResultDetailView {
  /// Composes a highlight share card from a past-results turn row and presents
  /// the share sheet (#1070). Re-applies ContentFilter to the persisted output
  /// (past-results stores *unfiltered* text — #1075), maps the run's model
  /// identifier to its short label so the card matches the live path, and
  /// no-ops if the utterance is empty or rendering fails.
  func shareHighlight(agent: String, output: TurnOutput, phaseType: PhaseType) {
    guard let text = output.primaryText(for: phaseType) else { return }
    guard
      let model = HighlightShareCard.Model(
        agent: agent,
        agentPosition: agentOrder.firstIndex(of: agent),
        rawUtterance: text,
        rawThought: output.secondaryText(for: phaseType),
        scenarioTitle: scenario?.name,
        modelName: ModelRegistry.shortDisplayName(forIdentifier: simulation?.modelIdentifier),
        linkURL: LocalizedPublicPages.sharedScenario(id: scenario?.id),
        contentFilter: contentFilter)
    else { return }
    // Offer the custom story-share sheet only when Instagram Stories is
    // actually available (installed + App ID configured); otherwise fall
    // straight through to the system share sheet — no UX change until the
    // feature is live (#1083).
    if InstagramStoriesSharer.isAvailableNow {
      highlightShareContext = HighlightShareContext(model: model, colorScheme: colorScheme)
    } else {
      highlightShareItem = HighlightCardImageRenderer.makeShareItem(
        model, colorScheme: colorScheme)
    }
  }
}
