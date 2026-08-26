package com.pastura.engine

/**
 * YAML fixture builders for [ScenarioLoaderTests].
 *
 * Kotlin counterpart of the private / file-scope helpers on Swift's
 * `ScenarioLoaderTests.swift` (`makeMinimalYAML()` / `makeMinimalYAML(phasesBlock:)`
 * / `makeYAMLWithAssignTarget`) and `ScenarioLoaderTests+Language.swift`
 * (`makeBaseYAML`). Collapsed into one file, mirroring
 * `ScenarioValidatorTestSupport.kt`'s precedent for this port series.
 */

/**
 * A two-persona (Alice / Bob), one-phase (`speak_all`) minimal scenario — the
 * "happy path" fixture reused across the top-level suite. Self-contained, so
 * `trimIndent()` is safe here (contrast [makeMinimalYAML] below, which builds
 * around a caller-supplied block instead).
 */
internal fun makeMinimalYAML(): String = """
    id: test_scenario
    language: ja
    name: Test
    description: A test scenario
    agents: 2
    rounds: 3
    context: You are in a game.
    personas:
      - name: Alice
        description: A strategist
      - name: Bob
        description: An optimist
    phases:
      - type: speak_all
        prompt: "Speak your mind."
        output:
          statement: string
          inner_thought: string
""".trimIndent()

/**
 * A two-persona (A / B) minimal scenario with [phasesBlock] — a caller-supplied
 * `phases:` block (optionally followed by top-level extra-data keys it
 * references) — substituted in place of a fixed phase list, for tests
 * exercising phase-field parsing.
 *
 * Built with [buildString] rather than a single `trimIndent()`'d template:
 * [phasesBlock] arrives already dedented to column 0 (each call site's own
 * `trimIndent()`'d literal), and re-running `trimIndent()` over the
 * concatenation would compute a common margin across both halves — which
 * silently mis-indents whichever side has the smaller natural margin.
 */
internal fun makeMinimalYAML(phasesBlock: String): String = buildString {
    appendLine("id: t")
    appendLine("language: ja")
    appendLine("name: T")
    appendLine("description: T")
    appendLine("agents: 2")
    appendLine("rounds: 1")
    appendLine("context: C")
    appendLine("personas:")
    appendLine("  - name: A")
    appendLine("    description: D")
    appendLine("  - name: B")
    appendLine("    description: D")
    append(phasesBlock)
}

/**
 * A two-persona (A / B) minimal `assign` scenario whose `target:` value is
 * [target] — for the strict `AssignTarget` parsing tests, which need an
 * otherwise-fixed fixture varying only that one token.
 */
internal fun makeYAMLWithAssignTarget(target: String): String = """
    id: t
    language: ja
    name: T
    description: T
    agents: 2
    rounds: 1
    context: C
    personas:
      - name: A
        description: D
      - name: B
        description: D
    phases:
      - type: assign
        source: topics
        target: $target
    topics:
      - x
""".trimIndent()

/**
 * A minimal scenario whose `language:` / `simulation_language:` lines are
 * present only when [language] / [simulationLanguage] are non-null — mirrors
 * Swift's `makeBaseYAML`, which omits the `language:` line entirely so
 * `rejectsLanguageAbsent` can exercise the missing-field path.
 */
internal fun makeBaseYAML(language: String? = null, simulationLanguage: String? = null): String {
    val lines = mutableListOf("id: t")
    if (language != null) lines += "language: $language"
    if (simulationLanguage != null) lines += "simulation_language: $simulationLanguage"
    lines += listOf(
        "name: T",
        "description: T",
        "agents: 2",
        "rounds: 1",
        "context: C",
        "personas:",
        "  - name: A",
        "    description: D",
        "  - name: B",
        "    description: D",
        "phases:",
        "  - type: speak_all",
        "    prompt: x",
        "    output:",
        "      statement: string",
    )
    return lines.joinToString("\n")
}
