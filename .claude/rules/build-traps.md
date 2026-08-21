---
paths:
  - "Pastura/Pastura/**/*.swift"
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/harness/**"
---

# Build & Lint Traps

Traps that fire when **adding or naming a Swift file**, in any layer and any target — hence the
globs above, which are the union of the two traps' reach.

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

## Prose ABOUT a directive is parsed AS one

The comment-command parser scans every `//` comment, so quoting a directive's
literal text while explaining it applies it. Writing `// swiftlint:disable X`
inside a paragraph about that trap is enough. Loud rather than silent — the
quote lands as a real command and draws `blanket_disable_command`, plus
`superfluous_disable_command` if adjacent backticks get swept into the rule
name — but the diagnostics name the rule you were describing, so they read as a
problem with the code rather than with the sentence.

**Apply**: in a **Swift** comment, name a directive rather than spelling it —
"a blanket `file_length` disable directive on line 6", not the text itself. The
example above is spelled out because this file is Markdown, which SwiftLint does
not scan; that asymmetry is the whole trap, so do not read the example as
licence to quote it in a `.swift` file.

## `swiftlint --path <file>` is not an option, and its error reads as "clean"

`swiftlint lint --path X` exits with `Error: Unknown option '--path'` (the
positional form `swiftlint lint [options] [paths...]` is the real one). A probe
that greps that output for a rule name finds nothing and concludes the rule did
not fire. Measured 2026-08-21 (0.65.0, #1505).

**Apply**: to test whether a rule fires, put the fixture **inside**
`.swiftlint.yml`'s `included:` tree and run the form the gates run
(`scripts/git-hooks/pre-commit`, `ci.yml`): `swiftlint lint --strict`. Two
things genuinely suppress a rule and are easy to mistake for "not enabled" — a
fixture outside `included:` (path-independent rules still fire there, so the run
looks live), and a file-level disable directive already in the target file.
