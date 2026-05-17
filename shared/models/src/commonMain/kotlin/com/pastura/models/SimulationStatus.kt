package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The execution status of a simulation.
 *
 * Kotlin port of `Pastura/Pastura/Models/SimulationStatus.swift`. Persisted
 * as the `status` column in `simulations` (see CLAUDE.md models-and-data).
 */
@Serializable
public enum class SimulationStatus {
    /** The simulation is actively running. */
    @SerialName("running")
    RUNNING,

    /** The simulation is paused and can be resumed. */
    @SerialName("paused")
    PAUSED,

    /** The simulation has finished all rounds successfully. */
    @SerialName("completed")
    COMPLETED,

    /**
     * The simulation ended due to an error (LLM load failure, event-pipeline
     * error, etc.). The error message is surfaced via the App layer's
     * SimulationViewModel; this case disambiguates failed runs from clean
     * completions at the DB level.
     */
    @SerialName("failed")
    FAILED,

    /**
     * The simulation was cancelled before natural completion — user-initiated
     * or memory-warning induced. Distinguished from [PAUSED] (resumable) and
     * [FAILED] (errored).
     */
    @SerialName("cancelled")
    CANCELLED,
}
