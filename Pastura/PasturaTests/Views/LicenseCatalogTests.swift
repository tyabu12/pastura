import Foundation
import Testing

@testable import Pastura

/// Completeness guards for the Licenses & Acknowledgements catalog (#506).
///
/// The model section cross-references `ModelRegistry` by exact id-set
/// equality, so adding a model descriptor without a license entry (or
/// leaving an orphan entry behind after removing one) fails here instead
/// of shipping a silently incomplete legal surface.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LicenseCatalogTests {

  @Test func everyEntryHasNonEmptyTextAndURL() {
    for entry in LicenseCatalog.libraries + LicenseCatalog.models {
      #expect(!entry.text.isEmpty, "Empty license text for \(entry.name)")
      #expect(entry.url != nil, "Missing upstream URL for \(entry.name)")
      #expect(!entry.licenseName.isEmpty, "Missing license name for \(entry.name)")
    }
  }

  @Test func modelEntriesCoverModelRegistryExactly() {
    let registryIDs = Set(ModelRegistry.catalog.map(\.id))
    let catalogIDs = Set(LicenseCatalog.models.compactMap(\.modelID))
    #expect(
      registryIDs == catalogIDs,
      "Model license entries must match ModelRegistry 1:1 — missing: \(registryIDs.subtracting(catalogIDs)), orphaned: \(catalogIDs.subtracting(registryIDs))"
    )
  }

  @Test func libraryTextsAreVerbatimMIT() {
    // Copyright-holder lines from the LICENSE files at the revisions
    // pinned in Package.resolved — pins verbatim-ness, not paraphrase.
    let expectedHolders = [
      "llama.swift": "Mattt",
      "llama.cpp": "The ggml authors",
      "GRDB.swift": "Gwendal Roué",
      "Yams": "JP Simard"
    ]
    for (name, holder) in expectedHolders {
      let entry = LicenseCatalog.libraries.first { $0.name == name }
      #expect(entry != nil, "Missing library entry: \(name)")
      guard let entry else { continue }
      #expect(entry.text.contains(holder), "\(name) text must carry copyright holder '\(holder)'")
      #expect(
        entry.text.contains("Permission is hereby granted"),
        "\(name) must embed the verbatim MIT permission text")
    }
  }
}
