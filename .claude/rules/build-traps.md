---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
---

# Build & Lint Traps

Traps that fire when **adding or naming a Swift file**, independent of which layer it lives in.
The SwiftUI catalog (`swiftui-traps.md`) is scoped to the UI layers, so these two would be
invisible to `Engine/` / `LLM/` / `Models/` / `Data/` / `Utilities/` and test work if they lived
there.

`Pastura.xcodeproj` declares **three** native targets — `Pastura`, `PasturaTests`,
`PasturaUITests` — and `.stringsdata` collides per-target, hence all three globs above.

**Carve-out**: `tools/harness` (SwiftPM, ADR-013) is swiftlint-linted (`.swiftlint.yml`
`included:`) so the directive trap applies there, but it ships no string catalog, so the
`.stringsdata` trap does not. It is deliberately left out of `paths:` rather than loading this
whole file for half its content — the harness is covered by `swift-testing-parallelism.md`'s
`tools/**` glob.

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
