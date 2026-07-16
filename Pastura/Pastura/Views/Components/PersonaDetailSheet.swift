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
///
/// When the persona carries a ``Persona/secret`` (#914), a collapsed-by-default
/// spoiler section renders below the description. This sheet is the reveal
/// surface for all three chat contexts at once (Simulation, Past Results, and
/// the DL demo replay all mount it).
struct PersonaDetailSheet: View {
  let persona: Persona
  let position: Int?

  @Environment(\.dismiss) private var dismiss

  /// Deliberately plain `@State`, NOT hoisted to a ViewModel: the
  /// re-projection-resets-`@State` trap (`swiftui-traps.md`) is *beneficial*
  /// here — re-presenting the sheet re-hides the secret, which IS the spoiler
  /// gate. No persisted reveal state is wanted.
  @State private var showSecret = false

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
          if let secret = persona.secret {
            secretSection(secret)
          }
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

  /// The collapsed-by-default spoiler. The chevron + mono UPPER tag mirror the
  /// `INNER VOICE` toggle in ``AgentOutputRow`` so the two "peek at hidden
  /// text" affordances read as one family; the tinted triangle carries the
  /// accent and the tag stays muted (moss-for-prefix / muted-for-body, per the
  /// design system).
  ///
  /// The family resemblance stops at the hit target: this uses a plain
  /// `.frame(minHeight: 44)`, where `AgentOutputRow` needs the `+16 / -16`
  /// negative-padding trick (a 44pt frame was tried and rolled back there in
  /// #171 for inflating visible whitespace). Deliberate — a `.medium`-detent
  /// sheet has no density pressure, so the plain frame buys the same HIG target
  /// without that trick's load-bearing-comment tax. Do NOT "reconcile" the two.
  @ViewBuilder
  private func secretSection(_ secret: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) { showSecret.toggle() }
      } label: {
        (Text(verbatim: showSecret ? "▾ " : "▸ ")
          .foregroundStyle(Color.moss)
          + Text(String(localized: "PEEK AT THEIR SECRET"))
          .foregroundStyle(Color.muted))
          .textStyle(Typography.thinkingTag)
          .frame(minHeight: 44, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // State-dependent *label* (not a hint): matches the sibling INNER VOICE
      // toggle in `AgentOutputRow`, and unlike a hint it can't be suppressed
      // in VoiceOver settings or announced late.
      .accessibilityLabel(Self.secretToggleAccessibilityLabel(showSecret: showSecret))

      if showSecret {
        Text(secret)
          .textStyle(Typography.bodyBubble)
          .foregroundStyle(Color.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
    }
  }

  /// VoiceOver label for the spoiler toggle, stated as the action the tap
  /// performs. `static` + pure so it is unit-testable without rendering the
  /// sheet (ADR-009) — mirrors `AgentOutputRow.thoughtToggleAccessibilityLabel`.
  static func secretToggleAccessibilityLabel(showSecret: Bool) -> String {
    showSecret
      ? String(localized: "Hide secret")
      : String(localized: "Peek at their secret")
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
