---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/harness/**"
---

# Build & Lint Traps

Traps that fire from **build configuration rather than from code** — naming a Swift file, placing
a lint directive, or excluding a block from a build slice. The globs above are the union of the
three traps' reach. The third lives here rather than in `swiftui-traps.md` because what it is about
is which slice compiles a block, not a SwiftUI construct: today's `#if !targetEnvironment(simulator)`
sites are all under `Views/` / `App/`, so both files' globs would reach them, and this file's are the
superset that still would if one appeared elsewhere. Enumerate before assuming a site is one —
`git grep -n '#if !targetEnvironment(simulator)'`; the un-negated `#if DEBUG || targetEnvironment(simulator)`
(e.g. `LLM/OllamaService.swift`) is the opposite condition and not an instance.

Duplicate base filenames fail the build in **every** Swift target: `swiftc` rejects them outright
(`filename "Foo.swift" used twice`) and SwiftPM errors on duplicate `.o` producers. The
`.stringsdata` wording below is just the app-target surface, where `SWIFT_EMIT_LOC_STRINGS = YES`.
The SwiftLint trap fires wherever `.swiftlint.yml` `included:` reaches.

## Duplicate base filename → `.stringsdata` collision

Two Swift files with the same **base name** in one target fail the build with
`error: Multiple commands produce '…/<Name>.stringsdata'` (each Swift file emits
one `<BaseName>.stringsdata`). Easy to hit under Pastura's
`PBXFileSystemSynchronizedRootGroup` — sync folder groups auto-include every new
file under `Pastura/`, so a duplicate base name **anywhere** in the tree (even
cross-layer) collides.

**Apply**: before adding a file, `find Pastura/Pastura -name '<Name>*.swift'`;
if taken, pick a distinct name (rename the type too if it also clashes). Case
study: #759 renamed a new `ScenarioSummary.swift` (Views) that collided with the
Data-layer `ScenarioSummary` → `ScenarioSummaryStrip`.

## SwiftLint directive placement around a `///` doc comment

A `swiftlint:disable[:next] X` directive can't cleanly suppress a rule on a
declaration that also carries a `///` doc comment — **both** placements fail:

- **Between the doc comment and the declaration** (a `// swiftlint:disable:next X`
  line separating `/// …` from the `func`): detaches the doc comment, firing
  `orphaned_doc_comment`.
- **Inside the `///` block** (`/// swiftlint:disable:next X`): a **no-op** under
  `swiftlint --strict` — the comment-command parser recognizes `//`-form only, so
  the warning upgrades to an error unsuppressed. It looks load-bearing but is
  untested until the body later crosses the threshold.

**Apply** — don't relocate the directive; remove the need for it:

- `function_body_length` → **extract a helper** so each body stays under the
  threshold. Ref: `BundledDemoReplaySource.loadOne` → `buildSourceOrSkip`.
- `identifier_name` (short domain identifiers like `ja` / `en`) → add a
  **`.swiftlint.yml` `identifier_name.excluded`** entry (ref: the `ja` / `en`
  exclusions consumed by `pickLanguage(_:ja:en:)`), or rename to 3+ chars.

## Compile-checking `#if !targetEnvironment(simulator)` code

Such blocks (today: the `SettingsView` model-management UI, `ModelSettingsRow`,
and one arm of `AppDependencies`) are excluded from the simulator build, which is
what `scripts/xcodebuild.sh build` and `scripts/ui-tour.sh` use — so a compile
error in one survives a green local build. **CI is not blind to them**: `ci.yml`'s
`release-build` job builds `-sdk iphoneos`, failing every iOS-touching PR — but in
**Release configuration only**, so a block behind `#if DEBUG` *and*
`!targetEnvironment(simulator)` would be compiled by no CI job (none exists today).

Compile-check locally without provisioning — signing is skipped and Swift compiles
before signing, so `** BUILD SUCCEEDED **` confirms the block compiles:

```bash
scripts/xcodebuild.sh build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

The wrapper passes no `-configuration`, so that is a **Debug** device build and it
does reach a `#if DEBUG` device-only block CI cannot. `-destination` is additive
rather than last-wins, so this refreshes the simulator slice alongside the device
one (measured: one invocation rebuilt both `Debug-iphoneos` and
`Debug-iphonesimulator`). **Layout / visual** still needs a real device — flag
device-QA explicitly in PRs touching these blocks.
