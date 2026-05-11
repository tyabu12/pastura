import SwiftUI

/// Single row inside the Settings → Models section. Renders the
/// descriptor's display name, vendor, file size, and current state,
/// plus a Menu whose actions depend on the state:
///
/// - `.notDownloaded / .error` → Download (disabled when another model
///   is already downloading — the sequential policy)
/// - `.downloading` → Cancel download
/// - `.ready` non-active → Use this model (switch active) + Delete
/// - `.ready` active → Delete is hidden (use `.cannotDeleteActive` is
///   pre-empted by the UI); Active badge shown
///
/// Destructive actions surface a `ConfirmationDialog` binding up to
/// the parent `SettingsView`, since a per-row dialog state would
/// conflict with the Menu teardown animation.
struct ModelSettingsRow: View {
  let descriptor: ModelDescriptor
  let state: ModelState
  let isActive: Bool
  /// Whether another descriptor is already `.downloading` — disables
  /// this row's Download action per `ModelManager`'s sequential policy.
  let otherDownloadInProgress: Bool
  /// True iff a simulation is currently running. Disables the
  /// "Use this model" action to avoid tearing down the loaded
  /// `LlamaCppService` mid-inference.
  let isSwitchLocked: Bool

  let onDownload: () -> Void
  let onCancel: () -> Void
  let onSwitchActive: () -> Void
  let onRequestDelete: () -> Void

  // MARK: - Trailing control

  /// Discriminator for what to render in the row's trailing slot.
  ///
  /// Extracted as a pure-logic enum so the (state, isActive,
  /// otherDownloadInProgress) → control kind mapping can be unit-tested
  /// without a SwiftUI host (ADR-009 view-testing strategy).
  ///
  /// `disabled: Bool` on `.downloadButton` is LOAD-BEARING — it carries
  /// the sequential-DL guard + cellular-consent multi-row guard
  /// (`.claude/rules/navigation.md` QA scenarios 16 & 17, ADR-007 §3.3 (c)).
  /// Collapsing this into a payload-less case would let a body refactor
  /// silently drop `.disabled(otherDownloadInProgress)` from the new
  /// direct download button.
  internal enum TrailingControl: Equatable {
    /// Direct download icon button. `disabled` mirrors
    /// `otherDownloadInProgress` so a competing row's mid-download or
    /// pending cellular-consent state propagates here.
    case downloadButton(disabled: Bool)
    /// Existing ellipsis Menu (Cancel / Use this model / Delete actions).
    case menu
    /// Nothing rendered — used for `.ready+active`, `.checking`, and
    /// `.unsupportedDevice` where there is no actionable trailing affordance.
    case none
  }

  /// Pure derivation of the trailing slot's control kind from
  /// `(state, isActive, otherDownloadInProgress)`. Internal so
  /// `ModelSettingsRowTrailingControlTests` can pin every case.
  internal var trailingControl: TrailingControl {
    switch state {
    case .notDownloaded, .error:
      return .downloadButton(disabled: otherDownloadInProgress)
    case .downloading:
      return .menu
    case .ready:
      return isActive ? .none : .menu
    case .checking, .unsupportedDevice:
      return .none
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xs) {
          Text(descriptor.displayName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ink)
          if isActive {
            ActiveBadge()
          }
        }
        HStack(spacing: Spacing.xs) {
          Text(descriptor.vendor)
            .font(.footnote)
            .foregroundStyle(Color.inkSecondary)
          Text("·").foregroundStyle(Color.muted)
          Text(Self.formattedFileSize(descriptor.fileSize))
            .textStyle(Typography.metaValue)
            .foregroundStyle(Color.metaStrongL3)
        }
        stateLabel
          .padding(.top, 2)
      }
      Spacer(minLength: 0)
      menu
        .foregroundStyle(Color.inkSecondary)
    }
    .padding(.vertical, Spacing.xxs)
  }

  // MARK: - State label

  @ViewBuilder
  private var stateLabel: some View {
    switch state {
    case .checking:
      Text(String(localized: "Loading…"))
        .font(.footnote)
        .foregroundStyle(Color.muted)
    case .unsupportedDevice:
      Text(String(localized: "Not supported on this device"))
        .font(.footnote)
        .foregroundStyle(Color.muted)
    case .notDownloaded:
      Text(String(localized: "Not downloaded"))
        .font(.footnote)
        .foregroundStyle(Color.inkSecondary)
    case .downloading(let progress):
      Text(
        String(
          localized: "Downloading \(Int(progress * 100))%"
        )
      )
      .font(.footnote)
      .foregroundStyle(Color.mossDark)
    case .ready:
      Text(String(localized: "Ready"))
        .font(.footnote)
        .foregroundStyle(Color.mossDark)
    case .error(let message):
      Text(String(localized: "Error: \(message)"))
        .font(.footnote)
        .foregroundStyle(Color.dangerInk)
        .lineLimit(2)
    }
  }

  // MARK: - Actions menu

  private var menu: some View {
    Menu {
      switch state {
      case .notDownloaded, .error:
        Button {
          onDownload()
        } label: {
          Label(
            String(localized: "Download"),
            systemImage: "arrow.down.circle")
        }
        .disabled(otherDownloadInProgress)

      case .downloading:
        Button(role: .destructive) {
          onCancel()
        } label: {
          Label(
            String(localized: "Cancel download"),
            systemImage: "xmark.circle")
        }

      case .ready:
        if !isActive {
          Button {
            onSwitchActive()
          } label: {
            Label(
              String(localized: "Use this model"),
              systemImage: "checkmark.circle")
          }
          .disabled(isSwitchLocked)
          Button(role: .destructive) {
            onRequestDelete()
          } label: {
            Label(
              String(localized: "Delete"),
              systemImage: "trash")
          }
        }

      case .checking, .unsupportedDevice:
        EmptyView()
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 18))
        .padding(.top, 2)
        .accessibilityLabel(
          String(localized: "\(descriptor.displayName) actions"))
    }
    .menuStyle(.borderlessButton)
  }

  // MARK: - Helpers

  static func formattedFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useGB]
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Active badge

private struct ActiveBadge: View {
  var body: some View {
    Text(String(localized: "Active"))
      .textStyle(Typography.tagPhase)
      .foregroundStyle(Color.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: Radius.button / 2)
          .fill(Color.moss))
  }
}
