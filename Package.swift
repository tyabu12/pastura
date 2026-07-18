// swift-tools-version: 6.2
//
// SwiftPM manifest for the headless macOS simulation harness (ADR-013).
//
// Compiles the iOS app's Engine/LLM/Models sources IN PLACE for macOS —
// nothing is duplicated or extracted. The Xcode project remains the build
// path for the iOS app; this manifest exists solely for `pastura-harness`
// and is the only consumer of the PASTURA_HARNESS_BUILD define.
//
// The pre-commit hook builds the Xcode project but NOT this package — run
// `swift build` after touching core sources or this manifest (guarded in CI
// by the harness-build job).
import PackageDescription

let package = Package(
  name: "pastura-harness",
  platforms: [
    .macOS(.v15)
  ],
  dependencies: [
    // Same packages, same pins as the app project
    // (Pastura/Pastura.xcodeproj — see Package.resolved there).
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(url: "https://github.com/mattt/llama.swift.git", exact: "2.8694.0")
  ],
  targets: [
    // Obj-C++ exception-catching bridge for llama_sampler_sample.
    // SwiftPM rejects mixed-language targets, so these two files live in
    // their own target (ADR-013 §4 C1). The .mm declares the llama symbol
    // via a manual extern "C" prototype — no llama.cpp header dependency;
    // the symbol resolves when the executable links LlamaSwift.
    .target(
      name: "PasturaSafeSampler",
      path: "Pastura/Pastura/LLM/SafeSampler",
      publicHeadersPath: ".",
      cxxSettings: [
        // SafeSampler.h gates its DEBUG-only test entry points on this
        // define; Xcode supplies it for app debug builds, SwiftPM does not.
        // Debug harness builds thus compile those C entry points with no
        // Swift caller (SafeSamplerTestHooks is !PASTURA_HARNESS_BUILD) —
        // intentionally dead symbols, kept so the .h contract stays uniform
        // across build paths.
        .define("DEBUG", to: "1", .when(configuration: .debug))
      ]
    ),
    // The app's core layers compiled as ONE module, mirroring the app
    // target. This exercises the layering's iOS-independence but does NOT
    // split per-layer modules — see ADR-013 §3 / §6 Q3.
    .target(
      name: "PasturaCore",
      dependencies: [
        "PasturaSafeSampler",
        .product(name: "Yams", package: "Yams"),
        .product(name: "LlamaSwift", package: "llama.swift")
      ],
      path: "Pastura/Pastura",
      // App-target-only entries are excluded explicitly — `sources:` alone
      // still makes SwiftPM warn about every unhandled sibling file.
      exclude: [
        "LLM/SafeSampler", "App", "Assets.xcassets", "Data", "Info.plist",
        "Pastura-Bridging-Header.h", "PasturaApp.swift", "PrivacyInfo.xcprivacy",
        "Resources", "Utilities", "Views"
      ],
      sources: ["Models", "LLM", "Engine"],
      swiftSettings: [
        // Mirrors the app target's SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
        // so the nonisolated annotations in core sources mean the same thing
        // under both build paths.
        .defaultIsolation(MainActor.self),
        // The Pattern-6-relevant member of the app target's
        // SWIFT_APPROACHABLE_CONCURRENCY = YES bundle (SE-0461): a
        // `nonisolated async` function runs on its *caller's* executor rather
        // than hopping to the global one. Without it this lane would compile
        // Engine/LLM under semantics the app does not use, and the
        // `swift build` gate that `.claude/rules/xcodebuild-cli.md` mandates
        // after Engine changes would be structurally blind to Pattern 6
        // (`.claude/rules/swift-isolation.md`). Only this member is mirrored —
        // the rest of the SWIFT_APPROACHABLE_CONCURRENCY bundle is a separate
        // decision, deliberately not folded in here (see #1169).
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .swiftLanguageMode(.v6),
        // Consumed by LLM/SafeSampler.swift to drop the bridging-header-era
        // DEBUG test hooks, whose C declarations the SwiftPM build cannot
        // see (cxxSettings defines do not reach the Swift clang importer).
        .define("PASTURA_HARNESS_BUILD")
      ]
    ),
    // Harness logic (run-log model, event mapping, arg parsing, run loop).
    // New code — default (nonisolated) isolation; cross-target surface uses
    // `package` visibility, not `public`.
    .target(
      name: "PasturaHarnessKit",
      dependencies: ["PasturaCore"],
      path: "tools/harness/Sources/PasturaHarnessKit",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .executableTarget(
      name: "pastura-harness",
      dependencies: ["PasturaHarnessKit", "PasturaCore"],
      path: "tools/harness/Sources/pastura-harness",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "PasturaHarnessKitTests",
      dependencies: ["PasturaHarnessKit"],
      path: "tools/harness/Tests/PasturaHarnessKitTests",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    )
  ]
)
