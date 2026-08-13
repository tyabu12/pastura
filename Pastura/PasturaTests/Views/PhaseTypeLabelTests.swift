import Testing

@testable import Pastura

/// Pins the LLM-vs-code color pairing on `PhaseTypeLabel`. After the
/// #171 token retrofit, the two branches land on the moss family (LLM,
/// accent) and the ink family (code, neutral) — a regression to
/// system-saturated `.purple` / `.orange` would reintroduce the §1
/// "no saturated colors" violation the retrofit explicitly fixes.
///
/// Each branch is now **two** tokens rather than one: `moss` / `inkSecondary`
/// fill the capsule, while the label reads the family's role token,
/// `mossOnWash` (#1327) / `inkOnWash` (#1408). An earlier revision of this
/// comment named only `Color.moss` and `Color.inkSecondary`, which stopped
/// being the label colour at #1327 — the structural check below never saw the
/// difference, for the reason in the next paragraph.
///
/// The color check is structural: we only verify that every LLM phase
/// picks the same side and every code phase picks the other, via the
/// `PhaseType.requiresLLM` contract. Testing the exact `Color` value
/// would require rendering the view, which PasturaTests avoids.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PhaseTypeLabelTests {

  @Test func llmPhasesRequireLLM() {
    // Any future change that moves a phase between LLM / code buckets
    // should surface here — PhaseTypeLabel's color choice pivots on
    // this exact predicate, so the invariant is the badge's contract.
    for phase in PhaseType.allCases {
      switch phase {
      case .speakAll, .speakEach, .vote, .choose, .reflect, .whisper, .narrate:
        #expect(phase.requiresLLM, "\(phase) is an LLM-driven phase")
      case .scoreCalc, .assign, .eliminate, .summarize, .conditional, .eventInject,
        .relationshipUpdate:
        #expect(!phase.requiresLLM, "\(phase) is a code-driven phase")
      }
    }
  }

  @Test func phaseTypeLabelCoversAllCases() {
    // Compile / instantiate every variant — catches a future PhaseType
    // addition that forgets to run through PhaseTypeLabel's LLM / code
    // split (e.g. adds a new enum case without updating `requiresLLM`).
    for phase in PhaseType.allCases {
      _ = PhaseTypeLabel(phaseType: phase)
    }
  }
}
