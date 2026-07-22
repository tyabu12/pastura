package com.pastura.engine

/**
 * Abstraction over language-of-text detection for LLM output adherence checks.
 *
 * Implementations classify a raw text snippet (typically the natural-language
 * fields of a parsed `TurnOutput`) and return an ISO 639-1 lowercase code
 * (`"ja"`, `"en"`, …) or `null` when the input is too short / too ambiguous to
 * classify above the implementation's confidence threshold.
 *
 * The concrete production implementation lives in the Swift App/ layer
 * (`NLLanguageDetector`, backed by Apple's `NLLanguageRecognizer`). Per ADR-010
 * D8, `import NaturalLanguage` is forbidden in Engine / LLM / Models / Data
 * layers — only this abstraction crosses the boundary. The Swift consumer
 * threads a nullable `(any LanguageDetector)?` (nil = skip the check), so there
 * is deliberately **no Noop impl** here; the interface is landed as an unwired
 * seam, mirroring [EngineLogger].
 *
 * Swift original: `Pastura/Pastura/LLM/LanguageDetector.swift`.
 * Ported for the ADR-023 §6 Stage-3 Engine migration (#501).
 */
internal interface LanguageDetector {
    /**
     * Detect the dominant natural language of [text].
     *
     * @param text The text to classify. Callers should join the
     *   natural-language fields of a parsed `TurnOutput` (excluding
     *   enum-constrained / option-bound fields whose values are author-supplied
     *   tokens) before passing.
     * @return An ISO 639-1 lowercase code (e.g., `"ja"`, `"en"`), or `null`
     *   when the classification confidence falls below the implementation's
     *   threshold. The consumer treats `null` as "skip the adherence check"
     *   rather than "mismatch".
     */
    fun detect(text: String): String?
}
