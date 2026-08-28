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
 * That consequence used to be load-bearing here in a way it was not in Swift:
 * before D3 (#1591), Kotlin's [ScenarioValidator] ported the run gate
 * (`validate`) without it being wired into [SimulationEngine], so an
 * unvalidated scenario could reach this function directly. D3 wires
 * `validate` into `SimulationEngine.run` via `preflightGate`, which rejects
 * `scenario.language !in Scenario.ACCEPTED_LANGUAGES` before any phase runs
 * — so the resolved string is now gated on the Kotlin run path too, matching
 * Swift. The `else` shape and the ja fallback are preserved as-is regardless
 * — a divergence here would make Stage-4 transcript parity fail for exactly
 * the inputs the validator is supposed to reject.
 *
 * **Layer note (ADR-010 D8, normative):** the Engine reads
 * `scenario.engineLanguage` only, never a device locale. This helper is
 * intentionally independent of any locale lookup, which would resolve against the
 * device and break the cross-language goal.
 *
 * The `ja` / `en` parameter names match the resolved language values verbatim so
 * callsites read as a Translation Table row.
 *
 * **Every literal passed here has a twin in the Swift original**, and the two must
 * render the same prompt or a cross-engine behaviour comparison measures two
 * different prompts rather than two engines. Editing one side only is a silent
 * half-change; `scripts/check-prompt-literal-parity.py` gates it (pre-commit + CI).
 * See `.claude/rules/engine.md` § "Prompt literals are paired with the Kotlin port"
 * for the allowlist procedure and for what the gate cannot see.
 *
 * Swift original: `Pastura/Pastura/Engine/LanguageDispatch.swift`.
 * Ported for the ADR-023 §6 Stage-2 gate slice (#501).
 */
internal fun pickLanguage(language: String, ja: String, en: String): String =
    when (language) {
        "en" -> en
        else -> ja
    }
