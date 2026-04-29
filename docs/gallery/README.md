# Pastura Gallery (Share Board)

Curated, read-only gallery of scenarios bundled with the Pastura iOS app.
The app fetches `gallery.json` from this directory and downloads individual
YAMLs listed in it when users tap **Try** on a Share Board entry.

## Trust Model

Gallery content is only as trustworthy as:

1. **GitHub transport (TLS)** — `gallery.json` and each YAML are fetched over
   HTTPS from `raw.githubusercontent.com`. The session disables cookies and
   restricts HTTP redirects to the same host.
2. **Curator's GitHub account** — whoever can push to this repository can
   change gallery content. There is no out-of-band signing or pinning in
   Phase 2. Future hardening (signed `gallery.json`, pinned-per-release
   hash) is out of scope.

Each YAML's bytes are verified against the `yaml_sha256` field in
`gallery.json` at download time. A mismatch fails loudly — no partial write
ever reaches the local DB.

## Schema

`gallery.json` is validated by `Models/GalleryScenario.swift` in the iOS
app. Fields:

```jsonc
{
  "version": 1,                              // increments on breaking schema changes
  "updated_at": "YYYY-MM-DDTHH:MM:SSZ",      // informational; ETag drives cache
  "scenarios": [
    {
      "id": "<scenario_id>",                 // MUST be globally unique (see Curation Rules)
      "title": "<display title>",
      "category": "social_psychology | game_theory | ethics | roleplay | creative | experimental",
      "description": "<1-2 sentences>",
      "author": "<github handle>",
      "recommended_model": "<model id>",     // must match a `ModelRegistry.catalog` id, e.g. "gemma-4-e2b-q4-k-m"
      "estimated_inferences": <int>,         // rough total LLM calls to complete
      "yaml_url": "<filename or absolute https URL>",  // resolved relative to gallery.json
      "yaml_sha256": "<lowercase hex>",      // SHA-256 of the YAML body
      "added_at": "YYYY-MM-DD"
    }
  ]
}
```

Unknown `category` values cause the app to reject the whole index — add a
new case to the Swift enum before shipping a JSON that uses it.

## Curation Rules

### Globally unique scenario ids

Gallery scenario ids **MUST NOT** collide with:

- Bundled presets: `prisoners_dilemma`, `bokete`, `word_wolf`.
- Any other gallery scenario id, current or historical.

The iOS app refuses to install a gallery scenario whose id matches an
existing local row with a different source. The fix is to rename the
gallery scenario (append `_v2`, `_alt`, etc.), regenerate its hash, and
update `gallery.json`.

### Suffix versioning

Prefer versioned ids (`asch_conformity_v1`, `asch_conformity_v2`) over
silent rewrites. Users who installed an earlier version see the **Update**
badge when a new hash for the same id is published; incompatible changes
should get a new id so old installs are preserved.

### Content guidelines

Gallery scenarios are public and curator-endorsed. Keep content:

- Educational or playful — aligned with Pastura's experimentation framing.
- Free of NG-word filter triggers (see `App/ContentFilter.swift`).
- Under ~50 total estimated inferences (Phase 0 learning).
- Not targeted harassment of real people.

## Adding a scenario

1. Draft a YAML following the existing examples. Keep it under 256 KiB
   (the app's per-YAML size cap).
2. Pick a unique id per the rules above.
3. Commit the YAML to `docs/gallery/<id>.yaml`.
4. Compute the SHA-256:
   ```sh
   shasum -a 256 docs/gallery/<id>.yaml
   ```
5. Add an entry to `gallery.json` with the hash, URL, and metadata.
6. **Run end-to-end before merging.** Push the feature branch, run a
   Debug build (so `PASTURA_GALLERY_BASE_URL` takes effect — see *Testing
   changes from a feature branch* below), and open the scenario from
   Share Board. Either (a) on a physical device with the bundled
   llama.cpp model already downloaded, or (b) in the iOS Simulator
   pointing at a local Ollama with the recommended model pulled. Run a
   full simulation and read the output. Confirm: rounds reach a
   meaningful conclusion (no truncation), agent personas come through
   clearly, and total inferences match the `estimated_inferences`
   ballpark. (Content-filter triggers are an authoring-time concern —
   see the *Content guidelines* bullet above and
   `App/ContentFilter.swift`.)
7. Open a PR. The scenario becomes available in the app after merge —
   the app uses ETag-conditional GET, so users pick up the update on
   their next Share Board visit.

## Files in this directory

- `gallery.json` — the index manifest the iOS app fetches.
- `<id>.yaml` — individual scenario definitions, one per listed entry.

## Testing changes from a feature branch

The app's hardcoded gallery base points at `main`. To preview a Share
Board change from a feature branch without merging, override the base
directory via a scheme environment variable (Debug builds only —
Release ignores it):

1. Xcode → **Edit Scheme** → **Run** → **Arguments** → **Environment Variables**.
2. Add `PASTURA_GALLERY_BASE_URL` =
   `https://raw.githubusercontent.com/tyabu12/pastura/<branch>/docs/gallery/`
3. Toggle the variable off (or delete it) before testing the production
   path.

The override is the **directory** containing `gallery.json` (trailing
slash optional — the app normalises it). The service appends
`gallery.json` and relative `yaml_url`s resolve against the same base,
so one env var covers both the index and its YAML siblings. Non-https
values fall back to the hardcoded base silently.
