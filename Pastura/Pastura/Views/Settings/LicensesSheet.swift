import SwiftUI

/// Sheet-presented screen listing open-source library and AI model licenses.
///
/// Presented from `SettingsView` → Legal section via `.sheet(isPresented:)`.
/// Contains its own `NavigationStack` (sheet-owned, exempt from root-stack
/// navigation rules in `.claude/rules/navigation.md`), so plain
/// `NavigationLink` is used for the detail push.
///
/// String keys in this file are `String(localized:)`-wrapped per CLAUDE.md.
/// `entry.name`, `entry.licenseName`, and `entry.text` are NOT wrapped —
/// they are proper nouns / verbatim legal text, deliberately untranslated
/// (documented in `LicenseCatalog.swift`).
struct LicensesSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(LicenseCatalog.libraries) { entry in
            NavigationLink(destination: LicenseDetailView(entry: entry)) {
              LicenseEntryRow(entry: entry)
            }
          }
        } header: {
          Text(String(localized: "Libraries"))
        }

        Section {
          ForEach(LicenseCatalog.models) { entry in
            NavigationLink(destination: LicenseDetailView(entry: entry)) {
              LicenseEntryRow(entry: entry)
            }
          }
        } header: {
          Text(String(localized: "AI Models"))
        }
      }
      .navigationTitle(String(localized: "Licenses & Acknowledgements"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done")) {
            dismiss()
          }
        }
      }
    }
  }
}

/// A single row in the license list showing the project name and license type.
private struct LicenseEntryRow: View {
  let entry: LicenseEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.name)
        .font(.body)
      Text(entry.licenseName)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

/// Detail view showing the full license text for a single entry.
///
/// Pushed inside `LicensesSheet`'s own `NavigationStack` via
/// `NavigationLink` — sheet-owned stacks are exempt from root-stack
/// navigation rules.
private struct LicenseDetailView: View {
  let entry: LicenseEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let url = entry.url {
          Link(String(localized: "View project page"), destination: url)
            .font(.callout)
        }
        // Supplemental policy/license documents (e.g. the Gemma
        // Prohibited Use Policy) — legally meaningful, so they get
        // tappable affordances instead of plain-text URLs in `text`.
        ForEach(entry.links) { link in
          if let url = link.url {
            Link(link.label, destination: url)
              .font(.callout)
          }
        }
        Text(entry.text)
          .font(.footnote)
          .monospaced()
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding()
    }
    .navigationTitle(entry.name)
    .navigationBarTitleDisplayMode(.inline)
  }
}
