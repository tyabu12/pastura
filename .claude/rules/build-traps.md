---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/harness/**"
---

# Build & Lint Traps

Traps that fire when **adding or naming a Swift file**, independent of which layer it lives in.
`swiftui-traps.md` is scoped to the UI layers, so these two would be invisible to `Engine/` /
`LLM/` / `Models/` / `Data/` / `Utilities/`, test, and harness work if they lived there.

The two have **different reach**, and the globs above are their union:

- **`.stringsdata` collision** — Xcode's localized-string-extraction step emits one
  `<BaseName>.stringsdata` per Swift file, per target, whether or not the target ships a string
  catalog (SPM dependencies like GRDB and Yams emit them too). `Pastura.xcodeproj` declares
  **three** native targets — `Pastura`, `PasturaTests`, `PasturaUITests` — so all three glob in.
  `tools/harness` is built by SwiftPM (`swift build`, ADR-013), which runs no such step, so this
  trap cannot fire there.
- **SwiftLint directive placement** — fires wherever `swiftlint` lints, which per
  `.swiftlint.yml` `included:` is `Pastura` **and** `tools/harness`. It is not a UI-layer
  concern: the canonical `pickLanguage` case sits in `Pastura/Pastura/Engine/`.

Injection verified from fresh subagent sessions on `Engine/`, `Views/`, `PasturaTests/` and
`PasturaUITests/` reads (#1312) — per `knowledge-layering.md`, a `paths:` edit cannot be
checked from the session that made it.

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
