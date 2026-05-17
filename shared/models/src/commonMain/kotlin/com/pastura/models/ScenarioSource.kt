package com.pastura.models

/**
 * Canonical source-type tags stored in `ScenarioRecord.sourceType`.
 *
 * Kotlin port of `Pastura/Pastura/Models/ScenarioSource.swift`. The Swift
 * original is `public enum ScenarioSourceType { public static let gallery
 * = "gallery" }` — a namespace for a single string constant. Kotlin idiom
 * is `object` + `const val`, giving the same call-site shape
 * (`ScenarioSourceType.GALLERY`).
 *
 * Used by the Data layer's readonly guard and the App layer's gallery
 * flow to distinguish how a scenario entered the local DB. A centralized
 * constant avoids scattering the string literal — a typo anywhere
 * becomes a compile error rather than a silent bypass.
 */
public object ScenarioSourceType {
    /** Row imported from Shared Scenarios (read-only gallery). */
    public const val GALLERY: String = "gallery"
}
