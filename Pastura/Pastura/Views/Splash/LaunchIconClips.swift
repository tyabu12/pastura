import SwiftUI

// The horizontal cut ratio lives in `LaunchAnimationConfig.iconCutRatio`
// so it is `nonisolated` and reachable from these `Shape.path(in:)`
// methods (which the SwiftUI runtime calls off the main actor).

/// Top portion of the launch icon — "sky" / brandmark.
///
/// Used by ``ColdSplashView`` as the base-layer clip so the icon's bottom
/// region (clipped by ``LaunchPastureClip``) can drift in on top without
/// doubling up the underlying grass/hill geometry.
///
/// **Corners (per ``LaunchAnimationConfig/iconCornerRadius``):**
/// - top-leading / top-trailing: rounded — match the icon's outer corners
/// - bottom-leading / bottom-trailing: square — meet the cut line cleanly
struct LaunchSkyClip: Shape {
  func path(in rect: CGRect) -> Path {
    let height = rect.height * LaunchAnimationConfig.iconCutRatio
    let subRect = CGRect(x: 0, y: 0, width: rect.width, height: height)
    let radius = LaunchAnimationConfig.iconCornerRadius
    let corners = RectangleCornerRadii(
      topLeading: radius,
      bottomLeading: 0,
      bottomTrailing: 0,
      topTrailing: radius
    )
    return UnevenRoundedRectangle(cornerRadii: corners).path(in: subRect)
  }
}

/// Bottom portion of the launch icon — grass + hill + sheep.
///
/// Used by ``ColdSplashView`` as the drift-layer clip. Offsetting this
/// layer horizontally creates the "羊と丘がのんびり右から流れてくる"
/// effect; ``LaunchSkyClip`` keeps the top half stationary so the two
/// halves form a complete icon when they settle.
///
/// **Corners (per ``LaunchAnimationConfig/iconCornerRadius``):**
/// - bottom-leading / bottom-trailing: rounded — match the icon's outer
///   corners
/// - top-leading / top-trailing: square — meet the cut line cleanly
struct LaunchPastureClip: Shape {
  func path(in rect: CGRect) -> Path {
    let originY = rect.height * LaunchAnimationConfig.iconCutRatio
    let subRect = CGRect(
      x: 0,
      y: originY,
      width: rect.width,
      height: rect.height - originY
    )
    let radius = LaunchAnimationConfig.iconCornerRadius
    let corners = RectangleCornerRadii(
      topLeading: 0,
      bottomLeading: radius,
      bottomTrailing: radius,
      topTrailing: 0
    )
    return UnevenRoundedRectangle(cornerRadii: corners).path(in: subRect)
  }
}
