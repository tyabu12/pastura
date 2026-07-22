package com.pastura.engine

import kotlin.math.abs

/**
 * Renders a perceiver's raw affinity row (`other name → score`) as a short
 * natural-language summary for injection into that agent's prompt.
 *
 * Gemma 4 E2B cannot read a numeric matrix, so the `relationship_update`
 * phase surfaces its affinities as prose ("You are wary of Ryuji") rather
 * than raw numbers. Only relationships whose magnitude reaches
 * [mentionThreshold] are mentioned, keeping the injected text bounded even
 * as scores accumulate across rounds. Language is chosen by the scenario's
 * engine language (ja / en), matching every other prompt-side string (#910).
 *
 * Swift original: `Pastura/Pastura/Engine/RelationshipVerbalizer.swift`.
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501).
 */
internal object RelationshipVerbalizer {
    /**
     * Minimum absolute affinity score for a relationship to be verbalized.
     * Below this the feeling is too weak to mention; the gate also caps the
     * prompt-length growth a fully-connected matrix would otherwise cause.
     */
    const val mentionThreshold = 2

    /**
     * Summarizes [affinities] (`other name → accumulated score`) as prose in
     * [language]. Mentions only entries with `abs(score) >= mentionThreshold`,
     * sorted by name for deterministic output, and returns `""` when nothing
     * crosses the threshold (the caller then injects an empty section).
     */
    fun summarize(affinities: Map<String, Int>, language: String): String {
        val notable = affinities
            .filter { abs(it.value) >= mentionThreshold }
            .toList()
            .sortedBy { it.first }
        if (notable.isEmpty()) return ""
        val clauses = notable.map { clause(other = it.first, score = it.second, language = language) }
        // ja sentences already carry a terminal 。 so they need no separator;
        // en sentences are space-separated.
        return clauses.joinToString(separator = pickLanguage(language, ja = "", en = " "))
    }

    private fun clause(other: String, score: Int, language: String): String {
        // `summarize` has already filtered to `abs(score) >= mentionThreshold`; the
        // warmth/wariness split is a pure sign test, decoupled from the magnitude gate.
        return if (score > 0) {
            pickLanguage(language, ja = "$other には好感を持っている。", en = "You feel warmly toward $other.")
        } else {
            pickLanguage(language, ja = "$other を警戒している。", en = "You are wary of $other.")
        }
    }
}
