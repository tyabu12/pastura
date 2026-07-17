package com.pastura.engine

/**
 * Selects the literal matching the effective Engine language for per-site
 * translation (ADR-010 D7).
 *
 * Callers pass `scenario.engineLanguage` (D5 / D6 row 1), which resolves
 * `simulationLanguage ?: language`.
 *
 * **Two-arm shape, and the `else` arm is deliberate.** Both `scenario.language`
 * and `scenario.simulationLanguage` are validator-gated to `{"ja", "en"}` (the
 * latter also accepts null), so the resolved string is effectively `{"ja", "en"}`
 * and `else` covers `"ja"` without a third defensive arm. This mirrors the Swift
 * original exactly — including the consequence that an unrecognised language
 * falls to **ja**, not en.
 *
 * That consequence is load-bearing here in a way it is not in Swift: Swift's
 * `ScenarioValidator` gates the input, but that validator is a Stage-3 port
 * (ADR-023 §4), so **no Kotlin gate enforces `{"ja", "en"}` yet**. Until it
 * lands, an unvalidated scenario reaches this function directly and silently
 * renders ja. Preserved as-is rather than "hardened" — a divergence here would
 * make Stage-4 transcript parity fail for exactly the inputs the validator is
 * supposed to reject.
 *
 * **Layer note (ADR-010 D8, normative):** the Engine reads
 * `scenario.engineLanguage` only, never a device locale. This helper is
 * intentionally independent of any locale lookup, which would resolve against the
 * device and break the cross-language goal.
 *
 * The `ja` / `en` parameter names match the resolved language values verbatim so
 * callsites read as a Translation Table row.
 *
 * Swift original: `Pastura/Pastura/Engine/LanguageDispatch.swift`.
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
internal fun pickLanguage(language: String, ja: String, en: String): String =
    when (language) {
        "en" -> en
        else -> ja
    }
