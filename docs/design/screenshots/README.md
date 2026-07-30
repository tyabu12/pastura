# Design-review screenshots

Generated PNGs of the app's major screens, for design review by humans
and agents. **The PNGs are gitignored** — regenerate on demand:

```bash
scripts/ui-tour.sh
```

The script runs `ScreenshotTourTests` (an XCUITest tour in `--ui-test`
launch mode: in-memory DB, `MockLLMService`, `StubGalleryService`,
deterministic seed content) on the UDID-pinned simulator and extracts
the attachments here. Requires `jq`. Takes a few minutes including the
build. Review-only capture — no assertion against stored references
(see the ADR-009 note); excluded from CI via `-skip-testing` in
`ci.yml`.

## Covered screens

| File | Screen |
|------|--------|
| `01-home.png` | Home (scenario list) |
| `02-scenario-detail.png` | Scenario detail (seeded scenario) |
| `03-editor.png` | Scenario editor (new scenario) |
| `04-shared-scenarios.png` | Shared Scenarios gallery |
| `05-gallery-detail.png` | Gallery scenario detail |
| `06-settings.png` | Settings |
| `07-results.png` | Past Results list (seeded fixture) |
| `08-result-detail.png` | Result detail timeline (seeded fixture) |
| `09-home-resume.png` | Home with the paused-run resume card |
| `10-home-empty.png` | Home empty state (no local scenarios) |
| `11-results-empty.png` | Past Results empty state (no results) |
| `12-search-no-match.png` | Browse search with no matching query |
| `13-gallery-empty.png` | Browse gallery loaded but empty ("No scenarios available yet") |
| `14-gallery-offline.png` | Browse gallery offline / load failure ("Gallery Unavailable") |

Rows 10–14 are the empty / error surfaces (#811) the ui-refine L5 (empty /
error / edge) and L6 (copy) lenses critique — seeded via
`--ui-test-seed-empty-inventory` / `--ui-test-seed-empty-gallery` /
`--ui-test-seed-gallery-offline` (see `ScreenshotTourTests`).

Content is fixture-driven (`StubScenarioSeeder` / `StubResultSeeder` /
`StubGalleryService`), so layouts are representative but copy is test
data — review structure, spacing, and tokens here; review real copy in
the app.

Where each screen sits in the navigation graph:
[`../navigation-map.md`](../navigation-map.md) (generated). Its
"Screenshot tour" table is derived from `ScreenshotTourTests` and lists
these stops in tour order with their wait anchors and how each is
reached (launch root / tab switch / push); the Mermaid graph above it
shows the root-stack push edges.

## Adding a screen

Add a tour stop in
`Pastura/PasturaUITests/ScreenshotTourTests.swift` (navigate, then
`capture(app, name: "NN-name", anchorId: ...)` on an element that only
exists once the screen has loaded), then add a row to the table above.

## Deferred (not yet captured)

- **ModelSelection / ModelDownload** — `--ui-test` mode bypasses the
  model-download flow entirely (straight to `.ready`); capturing these
  needs a dedicated launch-argument path.
- **Mid-run Simulation** — `MockLLMService` launches with an empty
  response queue under `--ui-test`, so a running simulation errors on
  first inference; capturing a live turn needs canned-response seeding
  via a launch argument.
- **Dark mode variant** — `scripts/store-shots.sh` /
  `scripts/marketing-shots.sh` deliberately pin the simulator to light
  appearance so captures stay deterministic; a dark set is deferred by
  choice, not blocked (dark itself renders now — the ADR-028 lock is
  gone).
- **Dynamic Type / ja locale variants** — single configuration only
  for now; variants multiply runtime and can be added per-screen when
  a review needs them.

## Animations

These are still screens. For *motion* review — the launch splash, and the
bubble-entrance / DL-dot animations that share the reachability blockers
noted above — see [`../motion/README.md`](../motion/README.md)
(`scripts/motion-capture.sh`): filmstrips + frame sequences captured the
same gitignored, local-only way.
