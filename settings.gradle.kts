// Pastura KMP integration (Issue #220 — KMP Models Layer Validation Spike).
// Per ADR-004 §6 (Draft) and #220 D1, Gradle modules mirror Swift layers:
// `shared/{models,llm,engine,data,utilities}`. W1 covers only `shared/models`.

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

// Modules are added incrementally per W1/W2/W3 deliverables.
// `:shared:models` lands in W1 Item 2.
