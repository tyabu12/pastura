// swift-tools-version: 6.2
import PackageDescription

// ADR-023 §6 Stage-2 gate — the Swift consumer of the KMP `shared/engine` slice.
//
// This is a SECOND, SEPARATE package manifest, deliberately NOT a target appended
// to the repository-root `Package.swift` (which is the ADR-013 `pastura-harness`
// manifest). The root manifest is built by the `harness-build` CI job with bare
// `swift build` / `swift test` (`.github/workflows/ci.yml`, "Build harness package"
// / "Run harness package tests"), which builds EVERY target it declares — so a
// `.binaryTarget` there would make every iOS-touching PR require an assembled
// XCFramework. That is exactly the coupling ADR-023 §6 rejects as option (B-root),
// and it is what the decision-B′ invariant forbids:
//
//     No per-PR lane acquires an XCFramework dependency — not the iOS xcodebuild,
//     not the root Package.swift harness build, not a dev `swift build`.
//
// Because the root manifest gives each of its targets an explicit `path:`, this
// nested package is not swept into the root graph, and a root `swift build` /
// `swift test` does not recurse into it. Both directions are checked per-PR by
// the `kmp-gate-isolation` job in `.github/workflows/ci.yml`.
//
// The XCFramework is a STAGED artifact — see README.md § "Assemble first".

/// Mirrors the **app target's** concurrency regime, not the root harness
/// package's. The two differ, and the difference is exactly what this gate has
/// to reproduce:
///
/// - `Pastura.xcodeproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` **and**
///   `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
/// - The root `Package.swift` mirrors only the first for `PasturaCore`.
///
/// The second is what enables `NonisolatedNonsendingByDefault` (SE-0461), under
/// which a `nonisolated async` function runs on its *caller's* executor. That is
/// the whole mechanism behind the Pattern 6 freeze
/// (`.claude/rules/swift-isolation.md`), and it is the named late-failure risk
/// for these adapters — so a package that omitted it would compile the adapters
/// under semantics the app does not use, and the Pattern 6 probe would prove
/// nothing about the real thing.
let gateSpikeSwiftSettings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .swiftLanguageMode(.v6)
]

let package = Package(
  name: "kmp-gate-spike",
  platforms: [.macOS(.v15)],
  targets: [
    // Staged by `scripts/stage-framework.sh` into `Frameworks/` (gitignored).
    // A local-path binary target is resolved when the package GRAPH loads, not
    // when the manifest is evaluated: `Package.swift` itself compiles fine on a
    // checkout that never ran the staging script, and `swift build` is what then
    // fails, reporting the missing artifact path.
    .binaryTarget(
      name: "PasturaSharedEngine",
      path: "Frameworks/PasturaSharedEngine.xcframework"
    ),

    // The two ADR-023 §10 permanent boundary adapters, plus the verbatim
    // `SuspendController` copy they relay through.
    .target(
      name: "KMPGateSpike",
      dependencies: ["PasturaSharedEngine"],
      swiftSettings: gateSpikeSwiftSettings
    ),

    // Gate measurements (i)/(ii)/(iii) — see README § "Gate measurements".
    .executableTarget(
      name: "kmp-gate-bench",
      dependencies: ["KMPGateSpike"],
      swiftSettings: gateSpikeSwiftSettings
    ),

    .testTarget(
      name: "KMPGateSpikeTests",
      dependencies: ["KMPGateSpike"],
      swiftSettings: gateSpikeSwiftSettings
    )
  ]
)
