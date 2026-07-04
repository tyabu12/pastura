import SwiftUI

/// A tapped ``Persona`` wrapped for presentation via `.sheet(item:)`.
///
/// `Persona` is a `Models`-layer value type without `Identifiable` — its
/// `name` is not guaranteed unique across the app, so the chat surfaces wrap
/// the persona here rather than conforming the model (which would leak a
/// presentation concern into `Models/` and risk `ForEach`/sheet id
/// collisions elsewhere). Follows the `.sheet(item:)` rule in
/// `swiftui-traps.md` — pass `Optional<Model>`, never `Int: Identifiable`.
///
/// ``position`` mirrors the agent's index in the scenario's persona list so
/// the sheet's avatar color matches the chat row it was opened from
/// (``SheepAvatar/Character/forAgent(_:position:)`` is position-priority).
struct PersonaSheetItem: Identifiable {
  let persona: Persona
  let position: Int?

  var id: String { persona.name }

  init(persona: Persona, position: Int? = nil) {
    self.persona = persona
    self.position = position
  }
}

/// Read-only sheet showing a single agent's persona, surfaced by tapping the
/// agent's avatar / name in the Simulation, Demo, or Past Results chat log
/// (#942).
///
/// Presentation-only — editing lives in `PersonaEditorSheet`. The chrome
/// mirrors ``ScoreboardSheet`` (NavigationStack + inline title + Close), and
/// the avatar + name header reuses the ``ViewerPredictionSheet`` row style.
/// The body renders ``Persona/description`` **verbatim**: scenarios author it
/// in the 【立場】【目的】 style, but the sheet imposes no structure so it stays
/// robust to any description format. Presented at `.medium` detent so the
/// conversation the user tapped from stays partly visible behind it.
struct PersonaDetailSheet: View {
  let persona: Persona
  var position: Int?

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          Text(persona.description)
            .textStyle(Typography.bodyBubble)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .padding(20)
      }
      .navigationTitle(String(localized: "Persona"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Close")) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium])
  }

  private var header: some View {
    HStack(spacing: 14) {
      // Decorative — identity is carried by the adjacent name `Text`;
      // `SheepAvatar`'s accessibility label is a color-slot name
      // ("Alice"/"Bob"…), not the agent's display name (see i18n rule
      // §"Audit triage").
      SheepAvatar(
        character: .forAgent(persona.name, position: position),
        size: 56
      )
      .accessibilityHidden(true)
      // Reuses `titleScenario` (the "primary entity name" anchor) — the
      // persona name is this sheet's primary heading, a semantic match, not
      // a coincidental size reuse.
      Text(persona.name)
        .textStyle(Typography.titleScenario)
        .foregroundStyle(Color.ink)
      Spacer(minLength: 0)
    }
  }
}
