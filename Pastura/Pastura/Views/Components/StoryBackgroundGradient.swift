import Foundation

/// Moss gradient colors for the Instagram Stories 9:16 background (#1083).
/// Instagram composites the 1:1 highlight card sticker onto this gradient, so
/// only the two solid endpoint colors are needed — the app renders no 9:16
/// image itself. Derived from the shared moss palette tokens (single source of
/// truth); the exact endpoints are a visual-sign-off surface (real-device QA).
enum StoryBackgroundGradient {
  /// Top gradient color — `PasturaPalette.moss`.
  static var topHex: String { PasturaPalette.moss.hexString }
  /// Bottom gradient color — `PasturaPalette.mossDark`.
  static var bottomHex: String { PasturaPalette.mossDark.hexString }
}
