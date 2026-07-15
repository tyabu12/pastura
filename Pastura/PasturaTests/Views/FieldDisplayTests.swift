import Testing

@testable import Pastura

/// Coverage guard for the output-field description display SSOT. `@MainActor`
/// because `FieldDisplay` is a default-MainActor Views type (matches
/// `PhaseTypeLabelTests`); MainActor can still call the nonisolated
/// `ScenarioConventions` statics.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FieldDisplayTests {

  /// Every canonical field the editor can seed onto a phase's `output:` schema:
  /// the primary + thought field of every phase type, plus the opt-in `mood`
  /// field (#913, seeded only when an author declares it).
  private var canonicalFields: Set<String> {
    var fields: Set<String> = ["mood"]
    for phaseType in PhaseType.allCases {
      if let primary = ScenarioConventions.primaryField(for: phaseType) { fields.insert(primary) }
      if let thought = ScenarioConventions.thoughtField(for: phaseType) { fields.insert(thought) }
    }
    return fields
  }

  /// Every canonical field must carry a description — a new canonical field
  /// fails here until it is described.
  @Test func everyCanonicalFieldHasADescription() {
    for field in canonicalFields {
      #expect(
        FieldDisplay.description(for: field) != nil,
        "Missing FieldDisplay.description for \(field)")
    }
  }

  /// A custom / non-canonical output key has no description, so the editor row
  /// shows no caption and the role pill is omitted.
  @Test func unknownFieldHasNoDescription() {
    #expect(FieldDisplay.description(for: "custom_field") == nil)
  }
}
