# Pastura Gallery (Shared Scenarios)

Curated, read-only gallery of scenarios bundled with the Pastura iOS app.
The app fetches `gallery.json` from this directory and downloads individual
YAMLs listed in it when users tap **Try** on a Shared Scenarios entry.

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
      "recommended_model": "<model id>",     // must match a `ModelRegistry.catalog` id — keep "gemma-4-e2b-q4-k-m", see below
      "estimated_inferences": <int>,         // rough total LLM calls to complete
      "agent_count": <int>,                  // optional; from YAML `agents:` — Browse row sheep cluster + footer
      "rounds": <int>,                       // optional; from YAML `rounds:` — Browse footer
      "phases": ["<phase_type>", ...],       // optional; ordered YAML phase types — Browse art-tile signature glyph
      "language": "ja | en",                 // ISO 639-1, mirrors the YAML `language:` — Browse language filter (ADR-010)
      "yaml_url": "<filename or absolute https URL>",  // resolved relative to gallery.json
      "yaml_sha256": "<lowercase hex>",      // SHA-256 of the YAML body
      "added_at": "YYYY-MM-DD"
    }
  ]
}
```

Unknown `category` values cause the app to reject the whole index — add a
new case to the Swift enum before shipping a JSON that uses it.

## Per-scenario YAML schema

The per-scenario YAML files (`docs/gallery/<id>.yaml`) follow Pastura's
top-level Scenario schema, validated by `Pastura/Pastura/Engine/ScenarioLoader.swift`.
This README documents only the gallery-specific concerns; for the full
field reference see `docs/specs/pastura-mvp-spec-v0_3.md` and the
ScenarioLoader source.

### `language` (required, ADR-010 D1)

Each gallery YAML MUST declare its language at the top level:

```yaml
id: asch_conformity_v1
language: ja        # ISO 639-1; "ja" or "en" per ADR-010 D1
name: ...
```

Allowed values: `ja`, `en` (ADR-010 D1 mandatory rule;
`scripts/check_demo_replay_drift.py`'s `ALLOWED_LANGUAGES` set
mirrors this for demo YAMLs). Missing or unknown values are
rejected by ScenarioLoader as `scenarioValidationFailed`.

Note: `language` is a property of the **YAML body** AND is denormalized
into the `gallery.json` index entry above. The index copy is required so
the Browse (さがす) tab can filter by language **before** downloading any
YAML — the in-app install-time read of the YAML body still happens, but it
is too late for the pre-download list filter. The two MUST agree, and three
layers enforce it: `scripts/add-gallery-entry.sh` **auto-derives** the index
`language` from the YAML `language:` scalar (so entries added through the
script are always in sync), `scripts/check-gallery-entry.sh --all` (pre-commit
+ CI gallery-drift gate) rejects any index entry whose `language` is missing,
out of range, or ≠ the YAML — covering hand-edits the script never touches —
and `GallerySeedYAMLTests.galleryLanguageMatchesYAML` pins index == YAML in
the iOS suite. (This complements — does not duplicate — ADR-010 D6's
`ScenarioRecord.language` column, which serves the installed-row Home /
Past Results consumer, a different surface that reads the local DB.)

## Current entries

Snapshot of the 4 shipped entries (informational; `gallery.json` is the
source of truth). Adding new entries follows the workflow in
**Adding a scenario** below.

| id | name (Japanese) | language | category | added_at |
|---|---|---|---|---|
| `asch_conformity_v1` | アッシュの同調実験 | `ja` | social_psychology | 2026-04-15 |
| `trolley_dilemma_v1` | トロッコ問題 | `ja` | ethics | 2026-04-15 |
| `detective_scene_v1` | 探偵の推理会議 | `ja` | roleplay | 2026-04-15 |
| `kinoko_takenoko_v1` | きのこの山 vs たけのこの里 | `ja` | creative | 2026-04-29 |

Per-language sibling entries (e.g., `asch_conformity_v1_en` with
`language: en`) ship independently of the bundled English presets — the
gallery is a separate distribution surface. The first en batch (universal
scenarios) lands via #850; once `gallery.json` carries ≥2 languages the
Browse (さがす) language-filter chip row auto-un-dormants (ADR-010 D6 /
#843). Cross-language canonical grouping uses `ScenarioRecord.sourceId`
per ADR-010 D4 — out of scope for this README.

## Curation Rules

### Globally unique scenario ids

Gallery scenario ids **MUST NOT** collide with:

- Bundled presets — see `Pastura/Pastura/App/PresetLoader.swift`
  `presetFileNames` for the current list (each entry's stem is the
  scenario id). `scripts/check-gallery-entry.sh` enumerates this
  directory at runtime and fails the commit on collision, so this
  README does not need to track additions to the bundle.
- Any other gallery scenario id, current or historical.

The iOS app refuses to install a gallery scenario whose id matches an
existing local row with a different source. The fix is to rename the
gallery scenario (append `_v2`, `_alt`, etc.) and re-run
`scripts/add-gallery-entry.sh`. To refresh an existing entry's hash
or metadata in place (without renaming), use
`scripts/add-gallery-entry.sh --update <id>` — see *Updating an
existing scenario* below.

### Suffix versioning

Prefer versioned ids (`asch_conformity_v1`, `asch_conformity_v2`) over
silent rewrites. Users who installed an earlier version see the **Update**
badge when a new hash for the same id is published; incompatible changes
should get a new id so old installs are preserved.

### Which model a new entry should recommend

**Keep `gemma-4-e2b-q4-k-m`.** It names the build the QAT rebuild replaced, and
that looks stale — it is not. `gallery.json` is fetched **live** from
`raw.githubusercontent.com/.../main/` by every already-shipped app version, so an
id a shipped build does not know degrades it to `RecommendedModelStatus.unknownModel`
and an "Unknown model (…)" badge the moment the change merges, with no release
involved. The app resolves it on its own side instead
(`ModelRegistry.recommendationTarget(for:state:)`) — forward to the QAT build
for anyone who does not already have the replaced one, and to whichever build
they can reach for free if they do — so a current install is steered correctly
without the feed naming it.

Revisit once the app versions predating the QAT descriptor are no longer worth
supporting. That descriptor first ships in the release **after** this lands
(`MARKETING_VERSION` is 1.1 at time of writing, so 1.2). App Store Connect's
per-version adoption breakdown is the instrument; where to set the bar is still
a call someone has to make.
Rationale and the full mechanism: ADR-002 § Amendment 2026-08-15 — ADD-and-keep.

### Content guidelines

Gallery scenarios are public and curator-endorsed. Keep content:

- Educational or playful — aligned with Pastura's experimentation framing.
- Free of NG-word filter triggers (see `App/ContentFilter.swift`).
- Under ~50 total estimated inferences (Phase 0 learning).
- Not targeted harassment of real people.

## Adding a scenario

### Promoting from the scenario factory

If the YAML came from a `/scenario-factory` cycle
(`data/factory/scenarios/<date>/`), it is already schema-valid and
field-tested — skip the from-scratch drafting and bridge it to a gallery
entry:

1. Copy it to `docs/gallery/<slug>_v1.yaml` and rename the YAML's `id:`
   from `factory_<date>_<slug>` to `<slug>_v1` (the file stem **must**
   equal `id:` — see *Globally unique scenario ids* above).
2. `estimated_inferences` = the run log's `run_start.estimated_inferences`
   (`data/factory/runs/<date>/<id>.jsonl`).
3. `category` is usually `creative` for the oogiri / comedy family.
4. Curate by the digest's judge scores — promote high scorers, hold back
   low-coherence or low-humor runs. The factory judge is a **quality**
   filter, NOT a content-safety screen, and gallery YAMLs do **not** pass
   through the blocklist gate (that gate is Presets-only). Apply the
   *Content guidelines* above yourself.

Steps 1–3 are automated by `scripts/promote-factory-to-gallery.sh`,
which copies + rewrites the YAML, extracts `estimated_inferences` from
the run log, defaults `category` / `recommended_model`, then delegates
registration to `add-gallery-entry.sh`:

```sh
bash scripts/promote-factory-to-gallery.sh <factory-id> \
  --description "<short card-friendly summary>"
```

`<factory-id>` is the YAML's `id:` (e.g. `factory_20260618_uso_kigen`);
the script derives the scenario / run-log paths and the default
`<slug>_v1` gallery id from it. Pass `--description` to write a clean
card summary — without it the factory YAML's description (which carries
curation meta-notes) is used verbatim and only a warning is printed (it
becomes a hard error under `--non-interactive`). Preview the derived
values first with `--dry-run`; `--help` lists every flag — notably
`--category` (default `creative`), `--recommended-model` (default
`gemma-4-e2b-q4-k-m` — deliberate, see § "Which model a new entry should
recommend"), `--id` (for a `_v2` re-promotion), and
`--scenario` / `--run-log` (to promote a
non-factory source YAML, e.g. an improved variant). **Step 4 (curation)
is still yours** — the script promotes the id you name and never picks
by score.

Then verify the scenario end-to-end (§3 below) and open a PR (§4) — the
script has already done §1's drafting and §2's registration.

### 1. Draft the YAML

Write `docs/gallery/<id>.yaml` following the existing examples. Keep
it under 256 KiB (the app's per-YAML size cap, enforced by both the
add script and `URLSessionGalleryService.yamlSizeLimit`). Pick an id
that satisfies *Globally unique scenario ids* above; the file stem
**must** equal the YAML's `id:` field — the gallery resolver
round-trips on `yaml_url.lastPathComponent → file`, and the add
script refuses a stem-vs-id mismatch.

### 2. Run `scripts/add-gallery-entry.sh`

```sh
bash scripts/add-gallery-entry.sh docs/gallery/<id>.yaml
```

The script:

- Parses `id`, `name`, `description` from the YAML.
- Computes `shasum -a 256` and emits the canonical hex.
- Bumps top-level `updated_at` to today (UTC, midnight) — guarded by a
  `max(now, existing)` monotonicity check that warns on backward clock
  skew.
- Prompts for the four non-derivable fields, with choice lists read
  from the Swift sources at runtime so this README does not duplicate
  enums or model-registry contents:
  - `category` — see `GalleryCategory.allCases` in
    `Pastura/Pastura/Models/GalleryScenario.swift`
  - `recommended_model` — see `ModelRegistry.catalog` in
    `Pastura/Pastura/App/ModelRegistry.swift`
  - `estimated_inferences` — positive integer (rough total LLM calls)
  - `added_at` — defaults to today, override with `--added-at YYYY-MM-DD`
- Writes `gallery.json` atomically (tmp + mv) and re-runs
  `scripts/check-gallery-entry.sh --all` as a post-write gate. Any
  failure restores the byte-identical original.

`bash scripts/add-gallery-entry.sh --help` prints the full flag list
including `--non-interactive` (CI scripting) and `--description`
(override the YAML's description for a shorter card-friendly summary).

### 3. Run the scenario end-to-end before merging

Push the feature branch, run a Debug build (so
`PASTURA_GALLERY_BASE_URL` takes effect — see *Testing changes from a
feature branch* below), and open the scenario from Shared Scenarios.
Either (a) on a physical device with the bundled llama.cpp model
already downloaded, or (b) in the iOS Simulator pointing at a local
Ollama with the recommended model pulled. Run a full simulation and
read the output. Confirm: rounds reach a meaningful conclusion (no
truncation), agent personas come through clearly, and total
inferences match the `estimated_inferences` ballpark.
(Content-filter triggers are an authoring-time concern — see the
*Content guidelines* bullet above and `App/ContentFilter.swift`.)

### 4. Open a PR

The scenario becomes available in the app after merge — the app uses
ETag-conditional GET, so users pick up the update on their next Share
Board visit.

## Updating an existing scenario

When you need to refresh an *existing* gallery entry (typically because
you edited its YAML and `yaml_sha256` is now stale, or you want to tweak
the gallery card metadata), use the script's `--update <id>` mode:

```sh
# Refresh the hash after editing docs/gallery/<id>.yaml.
# <yaml-path> defaults to docs/gallery/<id>.yaml; pass it explicitly
# only if your YAML lives elsewhere.
bash scripts/add-gallery-entry.sh --update <id>

# Tweak gallery-card metadata in place (no YAML edit needed):
bash scripts/add-gallery-entry.sh --update <id> \
  --recommended-model qwen-3-4b-q4-k-m \
  --estimated-inferences 25
```

In update mode:

- Fields not overridden by a flag are **preserved** from the existing
  `gallery.json` entry — `--non-interactive` works without forcing
  every field to be re-supplied.
- If the candidate entry is byte-identical to the existing one (no
  flag overrides AND unchanged YAML body), the script exits 0 with
  *No change needed* — `updated_at` is **not** bumped, so re-running
  is free.
- The confirmation prompt shows an old → new diff for changed fields
  only, with `(from YAML)` source labels on YAML-derived fields
  (`title` / `agent_count` / `rounds` / `phases` / `language` /
  `yaml_sha256`) so you can tell YAML-driven changes from flag-driven ones.

### What auto-syncs from YAML on `--update`?

| YAML source     | Gallery field   | Auto-syncs? | Why                                                                                                                       |
|-----------------|-----------------|-------------|---------------------------------------------------------------------------------------------------------------------------|
| (file body)     | `yaml_sha256`   | **Yes**     | Recomputed via `shasum -a 256` on every run — the whole point of `--update`.                                              |
| `name:`         | `title`         | **Yes**     | `GallerySeedYAMLTests.galleryTitleMatchesYAMLName` enforces byte-equality; can't drift.                                   |
| `description:`  | `description`   | **No**      | Curators commonly use `--description "shorter card summary"` to give the gallery card a tighter blurb than the YAML body. |
| `agents:`       | `agent_count`   | **Yes**     | YAML-derived fact; `GallerySeedYAMLTests.galleryAgentCountAndRoundsMatchYAML` enforces equality.                          |
| `rounds:`       | `rounds`        | **Yes**     | Same YAML-derived enforcement as `agent_count` (same test).                                                               |
| `phases[].type` | `phases`        | **Yes**     | Ordered phase types; `GallerySeedYAMLTests.galleryPhasesMatchYAML` enforces equality.                                     |
| `language:`     | `language`      | **Yes**     | ISO 639-1 (ja/en); `GallerySeedYAMLTests.galleryLanguageMatchesYAML` + `check-gallery-entry.sh` enforce equality.         |

If you actually want the gallery `description` to re-sync from the
YAML, pass it explicitly. One-liner that pulls the current YAML value:

```sh
bash scripts/add-gallery-entry.sh --update <id> \
  --description "$(python3 -c "import yaml; print(((yaml.safe_load(open('docs/gallery/<id>.yaml')).get('description') or '')).strip())")"
```

(The `(d or '')` guard mirrors the script — without it, a YAML with
`description: null` or `description:` (no value) would raise
`AttributeError` instead of cleanly resolving to an empty string.)

### Curator smoke test

Before opening the PR, run these four cases against your edit. The
current branch's `gallery.json` is the source of truth — `git checkout`
reverts each step.

1. **No-op** — re-run `--update <id>` after the first successful
   update with no further edits. Expected: `No change needed —
   candidate entry is byte-identical to existing (id=<id>).`, exit 0,
   no `gallery.json` mutation.
2. **Override-persist** — pass a flag whose value differs from the
   existing entry, e.g. `--update <id> --estimated-inferences 99
   --non-interactive`. Expected: `gallery.json` shows the new value;
   `updated_at` bumped. Then `git checkout docs/gallery/gallery.json`
   to revert.
3. **Typo / unknown id** — `bash scripts/add-gallery-entry.sh --update
   nonexistent_v999 --non-interactive`. The default YAML path resolves
   to `docs/gallery/nonexistent_v999.yaml`, which does not exist;
   expected exit 1 with `ERROR: file not found:`. (If the curator
   instead has a YAML on disk whose `id:` is not yet in
   `gallery.json` — the only way to actually reach the *id-not-in-
   gallery* branch — the script lists available ids and suggests
   dropping `--update`.)
4. **Revert** — `git checkout docs/gallery/gallery.json
   docs/gallery/<id>.yaml` to leave the working tree clean before
   commit / PR.

## Highlights (ADR-029)

A **highlight** is a short curated excerpt of a real on-device run, published
as `docs/gallery/highlights/<id>.json` and pinned from the entry by
`highlight_url` + `highlight_sha256`. It renders on the `/s/<id>/` landing
pages and on the app's gallery detail screen. Optional and rare, so most
entries have none.

Read `docs/decisions/ADR-029.md` before curating one. The spoiler policy,
the 8-entry cap and the trust model are decided there, not here. This section
covers the workflow and the taste calls the gate cannot make.

### Procedure

1. **Run the scenario on the harness** (75-170s each):

   ```sh
   .claude/skills/scenario-factory/scripts/run_scenario.sh \
     docs/gallery/<id>.yaml ~/Models/gemma-4-E2B-it-Q4_K_M.gguf \
     data/highlight-runs/<id>.jsonl 600
   ```

   `data/highlight-runs/` is gitignored. Keep the transcript until the
   highlight merges, since re-running gives different text.

2. **Read the transcript and choose the lines yourself.** Eligible lines are
   `agent_output` events from `speak_all` / `speak_each`, `statement` field,
   in rounds 1 through ⌈rounds/2⌉, with no outcome-class phase earlier in the
   same round. A retried run appends a second attempt to the same file and
   restarts round numbering, so only the final attempt is pickable. A later
   round is reachable, but only by passing `--window-override` at extraction,
   which records `window_override: true` in the file for the reviewer to weigh.
   ADR-029 makes human selection non-negotiable, and the tool refuses to choose.

3. **Write a selection file** and extract. The schema is in
   `scripts/gallery_highlight_extract.py`'s docstring.

   ```sh
   python3 scripts/gallery_highlight_extract.py \
     --run data/highlight-runs/<id>.jsonl --id <id> --selection <sel>.json
   ```

   `persona_index` is derived and never selectable. `source.model` is derived by
   default — the extractor resolves the harness's display name to a
   `ModelRegistry` id — and `--model` can override it, but only with a value
   that resolves to a registry id or a known `displayName`.

4. **Register it in `gallery.json`** by hand, adding `highlight_url` and
   `highlight_sha256` (the extractor prints the hash) between `yaml_sha256`
   and `added_at`.

5. **Verify**: `bash scripts/check-gallery-entry.sh --all` (needs PyYAML on top
   of `jq` / `shasum` — it hard-exits without it, which reads like a broken gate
   rather than a missing dependency).

6. **Show the excerpt and caption to a human for sign-off** before committing.
   The blocklist audit is necessary, not sufficient.

### Curation norms

The gate checks structure. Whether a highlight is worth publishing is a taste
call, and these are what the batches so far have taught.

- **Scenario fitness varies, and it is the biggest factor.** Scenarios whose
  product *is* the utterance (comedy, improv, one-liners) excerpt well.
  Scenarios whose core is the *situation* are weak, because ADR-029 bans
  `assign`-distributed values from the excerpt, the caption and the teaser
  alike, so the interesting part cannot be written down anywhere.
  `trolley_dilemma_v1` was run and rejected on exactly this: all three of its
  framings live in `assign`.
- **Never paraphrase `assign` content** in a caption or teaser. An excerpt that
  lets a reader *infer* the prompt is fine, and for a question-and-answer
  scenario that inference is the point.
- **Do not use an existing caption as a template.** The bar is quality, not
  sentence shape. Captions written to the same pattern read as filler when the
  gallery shows several side by side.
- **A hook fragment quoting part of the cast is already disclosed** by the
  app's heading ("Some of the personas behind these lines", pinned by
  `HookHeadingLocalizationTests`). That is what ADR-029's
  § Amendment 2026-08-08 requires, and it is structural. Saying so again in the
  caption is optional polish: `chin_jimaku_v1` states the count outright
  (「この抜粋を生んだ4人のうち、特にクセの強い2人の設定。」),
  `asch_conformity_v1` only implies it
  (「サクラ4人の"後"に答えさせられるナオキの設定。」), and both are accepted.
- **An `eliminate` scenario leaks its outcome through the excerpt's speaker
  set.** Quoting N speakers in round *k* and N−1 of those same speakers in
  round *k+1* identifies the eliminated speaker by omission. ADR-029's
  position rule is keyed to phase visibility within a round, so it cannot see
  this — it is purely a curation trap. More weakly, *any* round *k+1* quote
  proves that speaker survived round *k*. `oogiri_knockout_v1`'s batch-2
  excerpt is round 1 only, because its round-1 eliminee
  (`理屈っぽい教授モドキ`) was precisely the speaker a two-round excerpt would
  have dropped. The safe fallback is a single-round excerpt, which carries no
  elimination-order information at all.
- **Check a pick against the speaking persona's own `例:`.** A persona
  description's `例:` lines are part of the prompt, so when one of them
  happens to be an ideal answer to the topic, the model reproduces it
  verbatim rather than inventing anything. `oogiri_knockout_v1`'s
  `一言必殺のゼロ次` emitted its example line unchanged in two independent
  draws, so it is in neither the excerpt nor the hook fragment. Publishing
  such a line would show the flagship "real run" quoting its own prompt — and
  the full YAML is one tap away in the app, so a reader can see it. This bites
  hardest for a `yaml_hook` persona slice, since the excerpt and the `例:`
  would then render on the same screen.

**Excerpt** and **hook fragment** are different things. The excerpt is the
quoted conversation; the hook fragment is the slice of YAML shown beneath it.
Norms about one do not transfer to the other.

Avatar colours need no attention from a curator. Each excerpt entry carries the
speaker's `persona_index`, so any set of speakers renders in the same colours a
real run gives them.

### Updating a scenario that has a highlight

A highlight pins the exact YAML bytes it was generated from. Editing the
scenario body and running `--update` therefore fails with
`highlight: yaml_sha256 mismatch`, which is correct rather than a bug. Resolve
it **in the same PR**, one of two ways:

- Re-run the harness and re-extract, then re-register the new hash. The excerpt
  text will differ, so it needs a fresh sign-off.
- Delete `docs/gallery/highlights/<id>.json` and both `highlight_*` fields.

`--update` itself preserves the `highlight_*` fields, so a metadata-only change
(a tighter card description, say) needs none of this.

## What enforces this contract

Three independent gates catch drift between the YAML and its
`gallery.json` entry:

1. **`scripts/check-gallery-entry.sh`** — runs as a pre-commit hook
   when the staged diff touches any `.yaml` / `.json` under
   `docs/gallery/` (including `highlights/`). Validates SHA-256
   byte-match, size cap, id uniqueness across `gallery.json` + bundled
   presets, and `<stem>.yaml ↔ id: <stem>`. Highlight validation is
   delegated to `scripts/gallery_highlight_validate.py`, which re-derives
   every ADR-029 rule a highlight file plus its index entry can support —
   the enumeration lives in ADR-029 Decision 2, and `check_content`'s
   dispatch list is the code it mirrors. A hand-edited highlight never
   runs the extractor, so this is the enforcement point rather than that
   tool.
2. **CI `gallery-drift` job** — re-runs the same check on every PR
   (catches `--no-verify` commits and PRs landed via the GitHub web
   UI that bypass the local hook).
3. **`PasturaTests/.../GallerySeedYAMLTests.swift`** — pins the
   yaml_sha256, title==name, recommended_model ∈ ModelRegistry, and
   category enum invariants in the iOS test suite. Runs on every PR.

## Manual fallback (when the script can't be used)

If `scripts/add-gallery-entry.sh` is unavailable for some reason
(missing PyYAML, bash unavailable, etc.), the same manual flow covers
both adding a new entry and updating an existing one:

1. Compute `shasum -a 256 docs/gallery/<id>.yaml | awk '{print $1}'`.
2. Edit `gallery.json`:
   - **Adding**: append a new object to `.scenarios` with the hash,
     `yaml_url: <stem>.yaml`, and the four prompted fields above.
   - **Updating**: locate the existing object by `id` and rewrite its
     `yaml_sha256` (and any other fields the curator intended to
     change) in place. Preserve the array position.
3. Bump top-level `updated_at` to today UTC at midnight
   (`YYYY-MM-DDT00:00:00Z`).
4. Run `bash scripts/check-gallery-entry.sh --all` before committing —
   it catches every error the script would have caught.

## Files in this directory

- `gallery.json` — the index manifest the iOS app fetches.
- `<id>.yaml` — individual scenario definitions, one per listed entry.
- `highlights/<id>.json` — curated run excerpts for the few entries that have
  one (ADR-029; see § Highlights above).

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
