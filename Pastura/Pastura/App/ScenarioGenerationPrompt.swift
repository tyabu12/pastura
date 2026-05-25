import Foundation

/// A copyable prompt for generating YAML scenarios via an external LLM.
///
/// Surfaced by the ScenarioEditor YAML-mode toolbar's "Copy Gen Prompt"
/// affordance. Kept as a free namespace (rather than a static on
/// ``ScenarioEditorViewModel``) so the editor file stays focused on
/// dual-mode state management.
enum ScenarioGenerationPrompt {
  static let text = """
    Generate a YAML scenario for Pastura (AI multi-agent simulation).
    Required structure:

    id: unique_snake_case_id
    language: ja|en   # required: authoring language; drives Engine output
    name: Scenario Name
    description: Brief description
    agents: <number 2-10>
    rounds: <number 1-30>
    context: Shared context for all agents
    personas:
      - name: Agent Name
        description: Character description
    phases:
      - type: <speak_all|speak_each|vote|choose|score_calc|assign|eliminate|summarize>
        prompt: Prompt template (for LLM phases)
        output:
          field_name: string

    Available phase types: speak_all, speak_each, vote, choose, \
    score_calc (logic: prisoners_dilemma|vote_tally|wordwolf_judge), \
    assign (source: key, target: all), eliminate, summarize (template: text).

    The `language` field is mandatory and accepts only `ja` or `en`. \
    Write all user-facing strings (name, description, context, prompt, \
    template, persona name/description) in that language.
    """
}
