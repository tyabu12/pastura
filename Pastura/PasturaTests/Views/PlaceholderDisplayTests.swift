import Testing

@testable import Pastura

/// Coverage guard for the token→description display SSOT. `@MainActor` because
/// `PlaceholderDisplay` is a default-MainActor Views type (matches
/// `PhaseTypeLabelTests`); MainActor can still call the nonisolated
/// `PlaceholderAvailability` statics.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PlaceholderDisplayTests {

  /// The full set of `{token}`s the variable-insert sheet can surface: the union
  /// of every phase type's supplied set (both `choose` qualifiers) plus the
  /// cross-phase readable state.
  private var allSurfacedTokens: Set<String> {
    var tokens = PlaceholderAvailability.crossPhaseStateReadable
    for phaseType in PhaseType.allCases {
      tokens.formUnion(PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: true))
      tokens.formUnion(PlaceholderAvailability.supplied(for: phaseType, chooseRoundRobin: false))
    }
    return tokens
  }

  /// Every engine-supplied token the sheet can show must carry a description —
  /// a newly handler-injected placeholder fails here until it is described.
  @Test func everySurfacedTokenHasADescription() {
    for token in allSurfacedTokens {
      #expect(
        PlaceholderDisplay.description(for: token) != nil,
        "Missing PlaceholderDisplay.description for {\(token)}")
    }
  }

  /// An unknown / custom output key has no description, so the sheet omits it.
  @Test func unknownTokenHasNoDescription() {
    #expect(PlaceholderDisplay.description(for: "totally_custom_key") == nil)
  }
}
