import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Drag payload for a sub-phase within a `conditional` phase's branch.
///
/// `id` is sheet-session-scoped — it matches `EditablePhase.id` which is
/// assigned at editor-session time and is **not** persisted to disk. Never
/// serialize this value to a durable store.
struct SubPhaseDragPayload: Codable, Transferable {
  let id: UUID
  let sourceBranch: EditablePhase.Branch

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}

/// Drag payload for a top-level phase in the scenario editor.
///
/// `id` is sheet-session-scoped — it matches `EditablePhase.id` which is
/// assigned at editor-session time and is **not** persisted to disk. Never
/// serialize this value to a durable store.
struct TopLevelPhaseDragPayload: Codable, Transferable {
  let id: UUID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .data)
  }
}
