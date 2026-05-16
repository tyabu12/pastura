import SwiftUI

/// Rounded-corner clip that exposes the bottom-right region of an image.
///
/// Used by ``ColdSplashView`` to isolate the "sheep silhouette" region of
/// the launch icon so it can drift in horizontally as a separate layer on
/// top of the static base icon.
///
/// **Geometry, per design handoff:**
/// - Start: `(originX, originY) = (width × 0.50, height × 0.56)` — the
///   top-left of the exposed region. Mirrors the CSS reference
///   `clip-path: inset(56% 0 0 50% round 30px)`.
/// - The clip preserves the icon's rounded corners by inheriting the
///   container's `iconCornerRadius` via ``LaunchAnimationConfig``.
struct SheepClipShape: Shape {
  func path(in rect: CGRect) -> Path {
    let originX = rect.width * 0.5
    let originY = rect.height * 0.56
    let subRect = CGRect(
      x: originX,
      y: originY,
      width: rect.width - originX,
      height: rect.height - originY
    )
    // Apply the same corner radius as the icon container so the clipped
    // region's bottom-right corner stays rounded.
    let radius = LaunchAnimationConfig.iconCornerRadius
    return Path(roundedRect: subRect, cornerRadius: radius)
  }
}
