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
      "highlight_url": "highlights/<id>.json", // optional; ADR-029 curated run excerpt, resolved relative to gallery.json (see § Highlights)
      "highlight_sha256": "<lowercase hex>", // optional; present iff `highlight_url` is; SHA-256 of that file
      "min_engine_version": <int>,           // optional; ADR-020 D3 declared engine floor — an app whose `EngineSchemaVersion.current` is lower greys the card (D4); raising it past `GallerySeedYAMLTests.maxGalleryFloorWithoutDeepLink` trips a test on purpose (ADR-020 §12) — the first entry to declare `2` is tracked in #1662
      "featured": <int>,                     // optional; curator-assigned pin rank (ADR-025) — lower number sorts higher in Browse; `nil` = not pinned, falls through to added_at-descending order
      "added_at": "YYYY-MM-DD"
    }
  ]
}
```

Unknown `category` values cause the app to reject the whole index — add a
new case to the Swift enum before shipping a JSON that uses it.

`add-gallery-entry.sh --update` does not manage `highlight_url` /
`highlight_sha256` / `min_engine_version` / `featured` — see
§ "Updating an existing scenario" for exactly how it carries them forward.

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

**Keep `gemma-4-e2b-q4-k-m`** — do not repoint existing gallery entries to the
QAT id. `gallery.json` is fetched live by already-shipped app versions, so an id
they do not know shows an "Unknown model (…)" badge the moment the change
merges, with no release involved; the app resolves the actual recommendation on
its own side instead (`ModelRegistry.recommendationTarget(for:state:)`). Revisit
once app versions predating the QAT descriptor are no longer worth supporting —
it first ships in the release after this lands (`MARKETING_VERSION` is 1.1 at
time of writing, so 1.2), and App Store Connect's per-version adoption breakdown
is the instrument. Mechanism: ADR-002 § Amendment 2026-08-15 — ADD-and-keep.

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

Promoting from an `/orchestrate` worktree: the factory sources are gitignored
and exist only in the **main checkout**, while the script writes under the
current tree (`git rev-parse --show-toplevel` = the worktree). Pass
`--scenario` / `--run-log` as absolute main-checkout paths — source=main /
dest=worktree is the working combination.

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
  every field to be re-supplied. Any field this script does not
  manage (ADR-029's `highlight_*`, ADR-020's `min_engine_version` /
  `featured`) is carried forward unconditionally.
- Calling this script with no usable tty — CI, or an agent's Bash
  tool — **requires `--non-interactive`**. Without it, a missing
  required field or the confirmation prompt tries to read `/dev/tty`
  and fails.
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
   same round. Under a `conditional`, "the same round" is the **branch that
   ran**, not the flattened phase list — read the transcript's
   `conditional_evaluated` to see which one, and judge a pick against that
   branch's own earlier phases. A pick *after* a conditional is judged against
   both branches, since the excerpt records neither (ADR-029 Decision 3).
   A retried run appends a second attempt to the same file and
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
   and `added_at`. Bump the top-level `updated_at` to today (UTC) in the same
   commit — `add-gallery-entry.sh` does it on both `--add` and `--update`, to
   `max(today, existing)` so the field never regresses, but a highlight is
   registered by hand and no gate checks the field, so it is silently
   skippable. Keep the highlight file and its two index fields in **one**
   commit, by hand: nothing enforces it. `check-gallery-entry.sh` reads the
   **working tree**, not the index, so staging only the highlight still passes
   pre-commit, and CI validates the PR head where both are present — an orphan
   intermediate commit lands unnoticed and only bites on a bisect or a revert.

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
  caption is optional polish: `asch_conformity_v1` only implies the count
  (「サクラ4人の"後"に答えさせられるナオキの設定。」) and is accepted as is.
  A hook may only quote personas the excerpt above it actually speaks for —
  the heading claims they are "behind these lines", and the app cannot check
  that claim. Every shipped hook has been a subset of the excerpt's speakers.
  Nothing enforces it: a re-extract can change the speaker set while the hook
  fragment is carried over unread, which is exactly how #1577 nearly published
  a hook naming a persona who spoke none of its excerpt's lines. Re-check the
  pairing on every re-extract, not just when writing a hook from scratch.
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
- **Check a pick against the speaking persona's own worked examples** — the
  `例:` lines of a ja persona, the `e.g.` lines of an en one, whatever the
  YAML uses to show the character how to answer. Those lines are part of the
  prompt, so when one of them happens to be an ideal answer to the topic, the
  model reproduces it verbatim rather than inventing anything. The trap is the
  example, not the label: `iiwake_battle_v1_en`'s `Shameless Mac` opened a
  round-1 draw with `Honestly, you should be thanking me`, which is his `e.g.`
  line word for word, so the en batch quoted the other three speakers instead.
  `oogiri_knockout_v1`'s
  `一言必殺のゼロ次` emitted its example line unchanged in two independent
  draws, so the batch-2 excerpt kept it out of both the excerpt and the hook
  fragment; #1475 then replaced the example with one that answers none of
  the topics, and the current excerpt quotes ゼロ次 only because two fresh
  draws re-checked every round against the new `例:`. Publishing
  such a line would show the flagship "real run" quoting its own prompt — and
  the full YAML is one tap away in the app, so a reader can see it. This bites
  hardest for a `yaml_hook` persona slice, since the excerpt and the example
  would then render on the same screen — so for a hooked persona, also reject
  a pick that merely reuses the example's sentence frame (the same closing
  phrase with the nouns swapped), which the gate cannot see. One carve-out,
  applied by batch 5 (#1588): when the persona's own 【目的】 / `[Goal]`
  mandates the *property* the recurring frame realises — `格ゲー脳`'s
  command notation plus startup-frame count is spelled out in his 【目的】;
  `古武術師範`'s 「我が一族相伝『…』」 and The Ancient Sensei's `passed
  down …` are the one natural wording of a 【目的】 / `[Goal]` that demands
  a clan-and-lineage invocation every time — the recurring wording is
  persona-inherent rather than example-borrowed. Exempt that wording and
  judge what the line adds *outside* frame-plus-name. A line that is nothing
  but the frame with the name swapped (`翻訳調の刺客`, `The FGC Grinder`)
  still fails the hook bar; one that adds a clause of its own (`格ゲー脳`'s
  「これで世界は再び目覚めるのだ！」, `古武術師範`'s opener and 「血脈の証」)
  passes it. A frame that merely *recurs* across draws with no 【目的】
  behind it earns no exemption — that is the trap this bullet exists for.
  A concrete
  example inside 【目的】 is the same trap under a different label: #1570's
  `kinoko_takenoko_v1` fix first replaced the 【目的】 anchor with another
  quotable phrase (「NASAが牛乳を白く塗っている」) and a draw promptly borrowed
  it as a simile inside an otherwise original line — so describe the
  *property* the persona shows (「桁まで具体的な捏造数字」) and keep any
  quotable, complete phrase out of 【目的】 too. A persona whose gimmick *is*
  the non-sequitur (`seriffu_knockout_v1`'s `天然のんき子`) cannot carry a
  quotable example at all: an off-topic domestic remark is an ideal answer to
  every topic, so swapping the line for another one only moves the
  reproduction. #1592 replaced hers with a property description and she kept
  the gimmick in both check draws. The lead-in of an example is quotable too:
  #1589's first rewrite moved `中二の覇王`'s subject off the topic but kept a
  catchphrase opener (「闇に還れ……」), and 3 of 4 draws opened with it — the
  fix names the *kind* of opener and says it must differ every time.
  Frames the check draws left behind, to reject at pick time for a hooked
  persona: `hissatsu_naming_v1`'s `翻訳調の刺客` opens 「くらえ、これがオレ流の
  “X”だ」 in every draw (his 【目的】 asks for exactly that voice, so it is
  the persona, not a defect); `seriffu_knockout_v1`'s `大袈裟役者ガラ` closes
  on 「〜のだァァ！」, which his new `例:` also uses; `chin_jimaku_v1`'s
  `ネタバレ女王` opened her spoiler parenthetical with 「(なお、」 in every
  draw, borrowed from her `例:` (the parenthetical itself is what her 【目的】
  mandates, the 「なお」 was not) — #1626 removed the `例:` and wrote the
  opener as a property (no lead-in, start from the outcome fact, differ every
  time). Its first, property-only wording showed that a property alone can
  lose the *shape*: with no example left to show the parenthetical, she
  dropped it in 3 of 4 rounds (2 draws × 2) and put the spoiler in
  `inner_thought` instead. The shipped wording adds the footnote persona's
  shape phrasing — 「必ず字幕の末尾に「(〜)」」 plus 「括弧書きが無い字幕は
  失敗」 — and under it she kept the parenthetical and opened on the fact in
  4 of 4 rounds. So when an `例:` goes, check whether it was also the only
  statement of the output's *form*, and say the form explicitly.
  Note that
  `assign` with
  `target: all` hands out `topics:` in file order, one per round
  (`AssignHandler`), not at random — so an example that shadows a later topic
  (`熱血真面目バン`'s 二度寝 against `seriffu_knockout_v1` topic 4) is outside
  the window and safe, and a round-1 collision cannot be re-drawn away.
  `chin_jimaku_v1_en`, the en twin, carried the same opener latent in
  `Spoiler Queen Sofia`'s `e.g.` (`(Anyway,` — never borrowed in a shipped
  draw);
  #1667 removed it and ported the ja three-property wording. On en the
  persona wording alone did not land: she kept the parenthetical in 1 round
  of 4 under the first port and 0 of 4 under a second that spelled out the
  two-part form (once relocating the spoiler to `inner_thought`). The
  variable was not her block but the `speak_all` prompt — ja's says 「自分の
  【目的】に書かれた芸風を必ず守り」, en's only said "Keep it short and commit
  to the bit." Adding the same clause ("Stick to the act written in your
  [Goal]") restored the parenthetical in 4 of 4 rounds, each opening on the
  fact. So before spending draws on persona wording, diff the *phase prompt*
  against the sibling language's.
  The one carve-out is a
  scripted speaker who is *not* the hook: `asch_conformity_v1` / `_en` quote
  the confederates' literal lines (「答えはCです」, `It's C, no doubt.`) because
  the verbatim repetition *is* the phenomenon, and only the subject is hooked
  (#1593).
  **A prompt that quotes the phrase it forbids primes it.** `kyoyu_gyojo_v1`'s
  first #1595 rewrite banned 「〜さんの言うように」 by quoting it, and the tic
  left `statement` only to saturate `inner_thought` — the field the ban's
  wording did not obviously cover — with one draw producing the mangled
  「みんなが言うようにても」. State the ban as a property (「最初の一文は
  自分の事情から書く」), say which output fields it binds, and check every
  field the excerpt can quote, not just `statement`.
  **`zenin_sansei_ryokou_v1` excerpts are round 1 only.** After #1595 its
  round-1 lines are distinct, but in round 2 a member still copies the
  detail the previous speaker just raised (run6: リン's BGM list, echoed
  by タク next turn), and the model's own 絆／結束 opener returns without
  any seed in the YAML. Nothing gates this; pick from round 1.
  **Whether a draw trips this is partly luck, so re-check it per draw rather
  than per scenario.** An `event_inject` scenario picks its twist at random,
  and a draw that happens to inject the very situation a persona's `例:`
  answers will reproduce that example — `hapning_ranyu_v1`'s rejected batch-3
  draw injected 「突然の停電…」, which is exactly what `安定の正統派`'s
  `例:「停電? これでようやく私の顔面も定価になった」` answers. The published
  draw drew a different twist and is clean. A scenario is not "safe" because
  one draw came out clean; each draw is its own check, and a scenario whose
  worked examples shadow its own `topics:` / `events:` entries will keep
  costing draws until the YAML is fixed.
  **When every persona's example shadows the same topic, no draw can fix it
  and the hook is what has to move — but moving the hook is the stopgap, not
  the fix.** `chin_jimaku_v1_en` shipped all four `e.g.` lines rendering
  topic 1's LINE, and topic 1 is its only pickable round, so any `persona`
  hook would have printed its own example beside the excerpt. That batch
  published a `raw` hook of the `speak_all` phase instead, which is what the
  excerpt actually answers. #1577 then re-pointed all four examples at lines
  neither topic uses, and the entry is back on a `persona` hook; #1667 then
  removed `Spoiler Queen Sofia`'s example outright (its opener was
  borrowable, see the frame list above), so her block is the en entry's
  first with no `e.g.` at all. Reach for
  `raw` only while the YAML is still wrong: ADR-029 § Amendment 2026-08-08
  makes `persona` the default precisely so the app can draw the hook in the
  editor's vocabulary rather than as a monospace block. Fixing the YAML
  re-hashes it, so it forces a re-extract and a fresh sign-off
  (§ "Updating a scenario that has a highlight") — budget that before
  starting, not after the gate rejects the commit.
  **Moving the hook to another persona re-opens the example check for the
  new hookee.** A hook change does not touch the excerpt, so nothing forces a
  re-extract, and a line that passed the loose bar for an un-hooked speaker
  (verbatim reproduction only) is now on the strict hooked side (sentence
  frame too) without anyone having looked. When review re-points a hook,
  re-read the new hookee's excerpt lines against that persona's `例:` /
  `e.g.` before accepting the change (#1595).
- **Captions and teasers render verbatim — no Markdown.** The app draws both
  with `Text(verbatim:)` and the landing pages interpolate them as text, so
  backticks, asterisks and brackets ship as literal characters. Write
  `[Goal]` only when that bracket is literally in the YAML you are pointing
  at.
- **A persona that drops its own gimmick is not quotable, however good the
  line is.** `chin_jimaku_v1_en`'s `Trivia Todd` is defined entirely by the
  `(Note: …)` footnote his `[Goal]` calls his whole gimmick, and he has now
  omitted it in four draws across two YAML revisions, then in #1667's six
  draws across three more kept it in `statement` in 2 rounds of 12 — and in
  0 of the 4 rounds under the shipped wording, where the `speak_all` prompt
  now points at `[Goal]` and `Literal Larry` and `Spoiler Queen Sofia` held
  theirs 4 of 4; twice the footnote landed in `inner_thought` instead. The
  prompt clause that fixed the other three did not reach him. Quoting him
  would put a
  line that contradicts his own declared gimmick on the page. Its ja sibling's
  `直訳マシーンのボブ` fails the same way from the other side — in six draws
  across two revisions, the excerpt shipped before #1577 included, he wrote
  fluent Japanese
  where his 【目的】 demands collapsed word-for-word translationese. A `[Goal]`
  the model quietly ignores is a scenario-design problem, not a draw problem,
  so **an emphatic instruction is not evidence that it lands** — `Trivia Todd`
  carries the most forceful wording in either file and honours it least.
  What did land for `直訳マシーンのボブ` (#1581) was not more emphasis: his
  【目的】 now describes the *property* of the output (English word order,
  subjects and possessives never elided, idioms split word by word) and names
  the failure condition (natural Japanese = failed), and topic 1 grew from a
  four-word shout to a two-sentence line with enough words to mangle. Under
  that wording he held the gimmick in 2 draws of 2 (#1581's check draws), as
  did all four personas
  in round 1 of both draws — the pickable window; `ネタバレ女王` dropped hers
  in run 2's round 2, outside it. The six-of-six count above is the old
  wording's record and stays.
  Check the transcript, not the YAML. Dropping one speaker costs nothing —
  outside an `eliminate` scenario, a partial speaker set leaks no outcome (see
  the `eliminate` norm above).
  **One persona failing every draw can cost the entry its highlight, because
  the constraints multiply.** `chin_jimaku_v1` lost its highlight in #1577 to a
  chain, not to a single verdict: `直訳マシーンのボブ` failed six draws out of
  six, so no hook may quote him; a hook may only quote personas the excerpt
  speaks for; and in the one draw where the remaining three all held their
  【目的】, `ネタバレ女王`'s line reused her own `例:` frame, which bars hooking
  her. What was left was a two-persona slice resting on a `余計な情報のスズキ`
  line that itself only half-kept his 【目的】 — thin enough that deleting the
  highlight (§ "Updating a scenario that has a highlight", second route) beat
  publishing it. #1581's persona rewrite earned it back two days later: all
  four held their 【目的】 in round 1 of both check draws, and the re-published hook
  quoted `直訳マシーンのボブ` and `余計な情報のスズキ` — `ネタバレ女王` stayed
  excerpt-only, because she opened her parenthetical with her `例:`'s 「(なお、」
  in both draws (see the frame list above). #1626 then rewrote her opener as
  a property and re-published from a draw where all four held 【目的】 in
  round 1; the hook now quotes ボブ and 女王 (still two of four). Her block
  joins `天然のんき子` (#1592) and the two `asch_conformity` subjects as a
  hooked persona with no `例:` — here because the example was the defect.
  Count the *surviving* slices before spending draws: one persona out can
  eliminate every legal one.

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
- Re-extract from the existing transcript, admissible only when the YAML
  edit provably cannot affect any excerpted line — every pick's round/phase
  is unaffected (e.g. `event_inject no_repeat: true` changes only round-2+
  draws while the excerpt is round 1). Edit the YAML, run
  `add-gallery-entry.sh --update <id>` so `yaml_sha256` matches the file,
  then re-run `scripts/gallery_highlight_extract.py` with the same picks
  against the kept `data/highlight-runs/<id>.jsonl`. The extractor pins the
  *current* file's hash, so the new pin is honest about bytes but not about
  the run. Re-register `highlight_sha256`. The PR body must state the
  argument for why no picked line could differ — the gate hashes only the
  current file and cannot check this. If the teaser changes too, it needs a
  fresh sign-off like any other.

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
