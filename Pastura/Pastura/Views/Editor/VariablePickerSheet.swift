import SwiftUI

/// A searchable bottom sheet that lists the `{token}` placeholders available in
/// the current phase, each with a short description (``PlaceholderDisplay``), and
/// inserts the tapped token into the prompt / template at the caret.
///
/// Sheet-owned `NavigationStack` (exempt from the tab-stack `navigationDestination`
/// rule — `.claude/rules/navigation.md` § "Sheets … out of scope"). Presented via
/// `.sheet(isPresented:)` on the prompt / template editor's footer button, not a
/// second sibling `.sheet` on `PhaseEditorSheet.body` (which already presents the
/// nested sub-phase editor).
struct VariablePickerSheet: View {
  /// Tokens the current phase's handler supplies (shown under "In this phase").
  let thisPhase: [String]
  /// Cross-phase state tokens any prompt may read (shown under "From other phases").
  let crossPhase: [String]
  /// Called with the tapped token (bare identifier, no braces); the caller wraps
  /// it in `{…}` and splices it at the editor caret.
  let onInsert: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        group(title: String(localized: "In this phase"), tokens: filtered(thisPhase))
        group(title: String(localized: "From other phases"), tokens: filtered(crossPhase))
      }
      .navigationTitle(String(localized: "Insert variable"))
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: Text(String(localized: "Search variables")))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done")) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @ViewBuilder
  private func group(title: String, tokens: [String]) -> some View {
    if !tokens.isEmpty {
      Section {
        ForEach(tokens, id: \.self) { token in
          Button {
            onInsert(token)
            dismiss()
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(verbatim: "{\(token)}")
                .font(.body.monospaced())
                .foregroundStyle(Color.accentColor)
              if let description = PlaceholderDisplay.description(for: token) {
                Text(description)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text(title)
      }
    }
  }

  /// Case-insensitive filter over the token identifier and its description.
  private func filtered(_ tokens: [String]) -> [String] {
    let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { return tokens }
    return tokens.filter { token in
      token.contains(trimmed)
        || (PlaceholderDisplay.description(for: token)?.lowercased().contains(trimmed) ?? false)
    }
  }
}
