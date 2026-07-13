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
    // Always present the custom share sheet as the default surface (#1096); it
    // gates the Instagram destination internally on `isAvailableNow`. Its live
    // card preview means a rasterization failure can't blank the sheet — unlike
    // the old direct-to-system-sheet fallback, which presented nothing on nil.
    highlightShareContext = HighlightShareContext(model: model, colorScheme: colorScheme)
  }
}
