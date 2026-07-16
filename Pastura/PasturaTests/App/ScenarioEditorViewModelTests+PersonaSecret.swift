import Foundation
import Testing

@testable import Pastura

/// `EditablePersona` ↔ `Persona` round-trip for the hidden-agenda field (#914).
/// Sibling extension — no new `@Suite` (see `.claude/rules/testing.md`
/// § "Splitting a Suite Across Files").
extension ScenarioEditorViewModelTests {

  @Test func editablePersonaRoundTripsSecret() {
    let persona = Persona(name: "Alice", description: "A strategist", secret: "She sold the house")
    let editable = EditablePersona(from: persona)

    #expect(editable.secret == "She sold the house")
    #expect(editable.toPersona() == persona)
  }

  @Test func editablePersonaRoundTripsAbsentSecret() {
    let persona = Persona(name: "Alice", description: "A strategist")
    let editable = EditablePersona(from: persona)

    // Absent secret surfaces as the empty editing buffer, and maps back to nil
    // rather than `""` — the editor boundary's half of empty ≡ absent.
    #expect(editable.secret == "")
    #expect(editable.toPersona().secret == nil)
    #expect(editable.toPersona() == persona)
  }

  @Test func whitespaceOnlySecretMapsToNil() {
    let editable = EditablePersona(name: "Alice", description: "A strategist", secret: "  \n ")
    #expect(editable.toPersona().secret == nil)
  }

  @Test func secretIsTrimmedOnMapping() {
    let editable = EditablePersona(
      name: "Alice", description: "A strategist", secret: "  She sold the house  ")
    #expect(editable.toPersona().secret == "She sold the house")
  }
}
