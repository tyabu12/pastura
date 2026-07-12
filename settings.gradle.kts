// Pastura KMP integration (Issue #220 — KMP Models Layer Validation Spike).
// Per ADR-004 §6 (Draft) and #220 D1, Gradle modules mirror Swift layers:
// `shared/{models,llm,engine,data,utilities}`. `shared/models` landed as
// infrastructure in #501 Stage 1 PR-1; `shared/engine` is added here (PR-2) as
// an empty scaffold — the landing pad for the Stage 2-pre ConditionEvaluator
// port (ADR-023 §6). The remaining layer modules follow with their ports.

rootProject.name = "Pastura"

pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        google()
    }
}

include(":shared:models")
include(":shared:engine")
