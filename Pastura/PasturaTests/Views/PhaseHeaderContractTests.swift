import SwiftUI
import Testing

@testable import Pastura

/// Logic-only contract tests for `PhaseHeader` per ADR-009 (no
/// rendered-output assertions). Pins design-decision constants that
/// would silently regress under a refactor: the `minLeadingHeight`
/// floor (header height parity between Demo's 2-line leading and
/// Sim's single-line leading) and the `extendsIntoTopSafeArea`
/// default (Demo opts in; Sim/Results stay safe under the system
/// nav bar).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PhaseHeaderContractTests {

  // MARK: - minLeadingHeight

  @Test func minLeadingHeightIsPinnedTo32() {
    // 32pt fits Demo's 2-line typography stack (tagPhase ~9.5pt +
    // 3pt spacing + titlePhase ~13pt ≈ 25.5pt natural) with comfort
    // margin. Pinning catches a silent shrink that would let Sim's
    // single-line leading drop the header height below Demo's.
    #expect(PhaseHeader<EmptyView, EmptyView>.minLeadingHeight == 32)
  }

  // MARK: - extendsIntoTopSafeArea default

  @Test func extendsIntoTopSafeAreaDefaultsToFalse() {
    // Sim/Results are NavigationStack-pushed — the system nav bar
    // already paints the top safe area with `.ultraThinMaterial`,
    // so a default-true would risk doubled blur. Demo (no nav bar)
    // opts in explicitly via `extendsIntoTopSafeArea: true` to fill
    // the status bar / Dynamic Island region with matching frosted
    // material.
    let header = PhaseHeader(leading: { EmptyView() }, trailing: { EmptyView() })
    #expect(header.extendsIntoTopSafeArea == false)
  }

  @Test func extendsIntoTopSafeAreaCanBeOverridden() {
    let header = PhaseHeader(
      extendsIntoTopSafeArea: true,
      leading: { EmptyView() },
      trailing: { EmptyView() })
    #expect(header.extendsIntoTopSafeArea == true)
  }
}
