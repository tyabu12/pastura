import SwiftUI

// The editor's two stacked status banners. Split out of `ScenarioEditorView.swift`
// to keep that file under SwiftLint's `file_length` limit. The blocking
// `validationBanner` (structural / content / lint-error) sits above the
// non-blocking `suggestionsBanner` (semantic-lint warning/info, ADR-024 PR2);
// the warm `warningSoft` tone vs `dangerSoft` distinguishes advisory from Save-blocking.

extension ScenarioEditorView {
  // MARK: - Validation Banner

  var validationBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(viewModel.validationErrors, id: \.self) { error in
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color.warning)
          Text(error)
            .font(.caption)
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.dangerSoft)
  }

  // MARK: - Suggestions Banner

  /// Non-blocking semantic-lint findings (`.warning` / `.info`) from the
  /// linter, surfaced below the blocking validation banner (ADR-024 PR2). The
  /// warm `warningSoft` tone + "Suggestions" header distinguish it from the
  /// `dangerSoft` error banner so it reads as advisory, not a Save blocker.
  /// `enumerated().offset` supplies `ForEach` identity because `LintFinding` is
  /// `Equatable` but not `Hashable`, and a rule can fire on multiple phases.
  var suggestionsBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "Suggestions"))
        .font(.caption.bold())
        .foregroundStyle(Color.warningInk)
      ForEach(Array(viewModel.lintWarnings.enumerated()), id: \.offset) { _, finding in
        HStack(spacing: 6) {
          Image(
            systemName: finding.severity == .info
              ? "info.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(finding.severity == .info ? Color.info : Color.warning)
          Text(finding.message)
            .font(.caption)
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.warningSoft)
  }
}
