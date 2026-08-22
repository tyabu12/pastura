import SwiftUI

// The visual editor's scalar sections — Basic Info (ID / name / description /
// rounds) and Context. Split out of `ScenarioEditorView.swift` to keep that
// file under SwiftLint's `file_length` limit, the same way `+Banners` is.
// These members read only the internal `viewModel`, so no `private @State` on
// `ScenarioEditorView` had to widen — keep it that way, or the split stops
// being free. Only the two sections cross the file boundary; the rounds
// helpers stay `private` here. The Personas / Phases sections stay in the
// main file with the `@State` they drive.

extension ScenarioEditorView {
  // MARK: - Basic Info

  var basicInfoSection: some View {
    Section {
      TextField(String(localized: "Scenario ID"), text: $viewModel.scenarioId)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.body.monospaced())
      TextField(String(localized: "Name"), text: $viewModel.scenarioName)
        .accessibilityIdentifier("editor.titleField")
      TextField(
        String(localized: "Description"), text: $viewModel.scenarioDescription, axis: .vertical
      )
      .lineLimit(2...5)
      roundsControl
    } header: {
      // §2.2's ground rule (#1527): this `Form` sits on `screenBackground`
      // (`.scrollContentBackground(.hidden)` in `visualEditor`), so its system
      // headers follow the table like the `PasturaSection` ones — `--ink-2`.
      // The editor *sheets* keep the system ground and the system default;
      // ledger §6.3 enumerates them. Pinned by `MutedSweepLedgerTests`.
      Text(String(localized: "Basic Info"))
        .foregroundStyle(Color.inkSecondary)
    }
  }

  /// Slider + stepper hybrid for discrete integer values (1...30).
  /// Matches iOS HIG for discrete tunable values where both precise
  /// increments (±) and quick scrubbing (drag) are desirable.
  private var roundsControl: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(String(localized: "Rounds"))
        Spacer()
        Text(verbatim: "\(viewModel.rounds)")
          .monospacedDigit()
          .foregroundStyle(Color.inkSecondary)
      }
      HStack {
        Button {
          viewModel.rounds = max(1, viewModel.rounds - 1)
        } label: {
          Image(systemName: "minus.circle.fill")
            .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.rounds <= 1)

        Slider(value: roundsSliderBinding, in: 1...30, step: 1)

        Button {
          viewModel.rounds = min(30, viewModel.rounds + 1)
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.rounds >= 30)
      }
    }
  }

  private var roundsSliderBinding: Binding<Double> {
    Binding(
      get: { Double(viewModel.rounds) },
      set: { viewModel.rounds = Int($0) }
    )
  }

  var contextSection: some View {
    Section {
      TextEditor(text: $viewModel.context)
        .frame(minHeight: 88)
    } header: {
      // Same ground rule as `basicInfoSection` above.
      Text(String(localized: "Context"))
        .foregroundStyle(Color.inkSecondary)
    }
  }
}
