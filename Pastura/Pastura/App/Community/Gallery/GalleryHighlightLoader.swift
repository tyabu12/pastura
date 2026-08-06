import Foundation
import OSLog

/// Loads and verifies a gallery scenario's curated highlight (ADR-029).
///
/// Deliberately a **separate, detail-screen-scoped** loader rather than a
/// method on ``SharedScenariosViewModel``: that view model backs both the
/// Browse list and the detail screen, and its `load()` gates the whole
/// detail screen behind a spinner. A highlight is a decorative enrichment —
/// it must never sit on that critical path, must never delay or fail the
/// screen, and its lifetime is one detail-screen appearance.
///
/// Every verification failure hides the section (``highlight`` stays `nil`)
/// and logs one `.info` line naming the failed check — ADR-029 Decision 4:
/// a security warning the user cannot act on is worse than absence, but the
/// failure must not be silent to developers.
@Observable
@MainActor
final class GalleryHighlightLoader {

  /// The verified highlight to render, or `nil` for "show nothing" — which
  /// covers not-yet-loaded, no highlight declared, and every verification
  /// failure alike. The view cannot (and must not) distinguish them.
  private(set) var highlight: GalleryHighlight?

  /// The only `schema_version` this build knows how to render. A newer file
  /// is hidden rather than best-effort rendered (ADR-029 Decision 4).
  static let supportedSchemaVersion = 1

  private let galleryService: any GalleryService

  private static let logger = Logger(
    subsystem: "app.pastura.Pastura", category: "GalleryHighlight")

  init(galleryService: any GalleryService) {
    self.galleryService = galleryService
  }

  /// Fetches, verifies, and publishes the highlight for `scenario`.
  ///
  /// Safe to call repeatedly (driven by `.task(id:)` from the detail view):
  /// state is reset on entry so a second call never leaves a previous
  /// scenario's highlight on screen.
  func load(for scenario: GalleryScenario) async {
    highlight = nil

    guard let url = scenario.highlightURL, let expectedHash = scenario.highlightSHA256 else {
      // Both absent is the ordinary "no highlight" case — silent, no log.
      // Exactly one present means the index violated the both-or-neither
      // pairing the repo-side gate enforces, i.e. a tampered or broken
      // index: hide and say so.
      if scenario.highlightURL != nil || scenario.highlightSHA256 != nil {
        log(check: "half_pair", scenarioID: scenario.id)
      }
      return
    }

    let data: Data
    do {
      data = try await galleryService.fetchHighlightData(
        from: url, expectedSHA256: expectedHash)
    } catch {
      // Navigating away cancels the fetch; that is not a verification
      // failure, so it must not spam the log with `fetch_failed`.
      guard !isCancellation(error) else { return }
      log(check: checkName(for: error), scenarioID: scenario.id)
      return
    }

    // The fetch above is the only suspension point, so one post-`await`
    // cancellation check covers the whole remaining (synchronous) funnel.
    guard !Task.isCancelled else { return }

    let decoded: GalleryHighlight
    do {
      decoded = try JSONDecoder().decode(GalleryHighlight.self, from: data)
    } catch {
      log(check: "unparseable", scenarioID: scenario.id)
      return
    }

    guard decoded.schemaVersion == Self.supportedSchemaVersion else {
      log(check: "unknown_schema_version", scenarioID: scenario.id)
      return
    }

    // An *absent* `content_filter_applied` key already failed the decode
    // above — the model declares it non-optional precisely so a malformed
    // file cannot pass as audited. This guard covers an explicit `false`.
    guard decoded.contentFilterApplied else {
      log(check: "content_filter_not_attested", scenarioID: scenario.id)
      return
    }

    // The schema caps the excerpt at 8 entries but has no floor; an empty
    // section would render as a titled void.
    guard !decoded.excerpt.isEmpty else {
      log(check: "empty_excerpt", scenarioID: scenario.id)
      return
    }

    // Every line's phase must map to a `PhaseType` this build knows.
    //
    // This is not about malformed content — the extractor and the repo-side
    // gate both hard-fail on an unknown phase (ADR-029 Decision 2), so a
    // published file is always mappable by *some* build. What it guards is
    // **version skew**: a highlight published after a new `PhaseType` lands
    // (ADR-029 revisit trigger 1) read by an app that predates the case.
    //
    // Whole section, not just the offending row, because an excerpt is a
    // *quotation* — the section's claim is that these lines, in this order,
    // are what happened. Dropping one silently rewrites the passage while
    // still presenting it as the record. That is the opposite trade-off from
    // `GalleryScenarioDetailFormat.phaseSteps`, which lenient-skips: there
    // every rendered step stays true and a gap merely understates the
    // scenario's structure.
    //
    // It also keeps `PhaseType` non-optional the whole way down the render
    // path, so the run figure never has to invent a fallback badge for a
    // phase it cannot name.
    guard decoded.excerpt.allSatisfy({ PhaseType(rawValue: $0.phase) != nil }) else {
      log(check: "excerpt_phase_unknown", scenarioID: scenario.id)
      return
    }

    highlight = decoded
  }

  // MARK: - Private

  private func checkName(for error: Error) -> String {
    guard let serviceError = error as? GalleryServiceError else { return "fetch_failed" }
    switch serviceError {
    case .hashMismatch: return "hash_mismatch"
    case .responseTooLarge: return "size_limit"
    case .invalidResponse, .unexpectedStatus, .corruptedCache: return "fetch_failed"
    }
  }

  private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
  }

  /// Both interpolations are `.public` by design: the check name is a
  /// compile-time constant from this file, and a gallery scenario id is a
  /// public catalog identifier — not user content. Highlight *content* is
  /// never logged.
  private func log(check: String, scenarioID: String) {
    Self.logger.info(
      "highlight hidden: check=\(check, privacy: .public) scenario=\(scenarioID, privacy: .public)")
  }
}
