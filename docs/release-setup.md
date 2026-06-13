# Release Setup — first-time bootstrap (maintainers)

A beginner-friendly, one-time walkthrough to unblock Pastura's **first**
TestFlight upload. After this is done, cutting a release is just running the
[`/release`](../.claude/skills/release/SKILL.md) skill, which drives
[`scripts/release.sh`](../scripts/release.sh) per
[ADR-014](decisions/ADR-014.md).

These steps are **operator-only** (they need the Apple Developer account) and
are performed **once**. The Apple Developer Program membership is already
active. Allow 30–60 minutes the first time.

> 🔐 The App Store Connect API key (`.p8`) is a credential. Never paste its
> contents into chat, commits, or any in-repo file. It lives outside the repo;
> only its file path is referenced. See [§ Security](#security) below.

## Phase 1 — Register the Bundle ID

The identifier `app.pastura.Pastura` must exist in the Apple Developer portal
before an app record can use it.

1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles**
2. **Identifiers** → **＋** → **App IDs** → **App**
3. **Description**: `Pastura` · **Bundle ID**: **Explicit** → `app.pastura.Pastura`
4. Leave capabilities at defaults → **Continue** → **Register**

(If it already appears in the Identifiers list, skip this phase.)

## Phase 2 — Create the App Store Connect app record

1. https://appstoreconnect.apple.com → **Apps** → **＋** → **New App**
2. Fill in:
   - **Platforms**: iOS
   - **Name**: `Pastura - Local LLMs simulator`
     — The store **Name** must be globally unique; plain "Pastura" was already
     reserved by another developer. This does **not** change the home-screen
     name, which comes from the app's own `CFBundleName` / `CFBundleDisplayName`
     and stays **Pastura**.
   - **Primary Language**: your choice (e.g. Japanese or English)
   - **Bundle ID**: select `app.pastura.Pastura`
   - **SKU**: any internal id, e.g. `pastura-ios` (not user-visible)
   - **User Access**: Full Access
3. **Create**

> The App Store **subtitle** (`Like stargazing, but for LLMs`) is part of the
> *version's store listing*, set later at App Store submission (Phase 3 of the
> roadmap) — there is no subtitle field at record-creation time, and TestFlight
> does not need it.

## Phase 3 — Generate the App Store Connect API key

1. App Store Connect → **Users and Access** → **Integrations** →
   **App Store Connect API** → **Team Keys**
2. Accept the API access agreement if prompted.
3. **Generate API Key (＋)** — **Name**: `pastura-release` · **Access**:
   **App Manager** (minimum) → **Generate**
4. **Download** the key → `AuthKey_XXXXXXXXXX.p8`.
   ⚠️ **Downloadable only once.** Lose it → revoke and regenerate.
5. Note two values from this screen:
   - **Key ID** — the 10-character id (the `XXXXXXXXXX` in the filename)
   - **Issuer ID** — the UUID shown above the keys table (shared per team)

## Phase 4 — Store the key and create `fastlane/.env`

Keep the `.p8` **outside the repo** and lock down its permissions:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Create the project-scoped env file from the template (it is gitignored;
**not** `~/.zshrc` — no need to pollute every shell, and fastlane auto-loads
`fastlane/.env`):

```bash
cd ~/Work/pastura
cp fastlane/.env.example fastlane/.env
```

Edit `fastlane/.env` with your real values (absolute path, no `~`/`$HOME`):

```
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=12a3b456-7890-....
ASC_KEY_PATH=/Users/<you>/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Confirm git will never see it:

```bash
git check-ignore fastlane/.env    # → prints "fastlane/.env" (ignored)
```

## Phase 5 — Establish the distribution certificate (one Xcode Archive)

`scripts/release.sh` archives headlessly, which needs a distribution
certificate + App Store provisioning profile to already exist. The simplest
way to mint them the first time is one GUI Archive:

1. Open `Pastura/Pastura.xcodeproj` in Xcode.
2. **Xcode → Settings → Accounts**: ensure an Apple ID on team `52G26234A3`
   is signed in.
3. Set the run destination to **Any iOS Device (arm64)** (Archive is disabled
   for simulators).
4. **Product → Archive**. Automatic signing creates the distribution
   certificate + App Store profile. When the Organizer opens, you can stop —
   the actual upload is handled by `/release`.

## Phase 6 — Install fastlane and verify

```bash
cd ~/Work/pastura
bundle install            # generates Gemfile.lock (recommend committing it)
```

Confirm the API key authenticates, with no side effects (queries the latest
TestFlight build number — returns `0` for a brand-new app):

```bash
TF_BUILD_OUT=/tmp/tf bundle exec fastlane ios latest_tf_build version:1.0
cat /tmp/tf               # 0 → the key works and fastlane read fastlane/.env
```

> If `bundle install` fails on the system Ruby (2.6.x), install a newer Ruby
> (`brew install ruby`) and re-run.

## Done — cut the release

Everything above is one-time. From now on:

```
/release
```

The skill proposes the version bump, synthesizes the "What to Test" notes for
your review, runs `scripts/release.sh --dry-run` to show the preflight, and —
after a mandatory confirmation — archives, uploads to TestFlight, and tags.

## Security

- The `.p8` is the only real secret. It stays at
  `~/.appstoreconnect/private_keys/` (outside the repo), `chmod 600`. Only its
  path is referenced from `fastlane/.env`.
- `fastlane/.env` is gitignored and holds identifiers only; `*.p8` is globally
  gitignored and `scripts/p8-precommit-gate.sh` refuses any staged `.p8`.
- **If the key leaks** (committed, shared, lost): revoke it immediately in
  App Store Connect → Users and Access → Integrations → App Store Connect API →
  (select the key) → **Revoke**, then regenerate and update `fastlane/.env`.
  See the `/release` skill's revocation section and
  [`docs/security/release-checklist.md`](security/release-checklist.md) § 4.

## Sources

- [App Store Connect API — Apple Developer Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Create an app record — Apple Developer Help](https://developer.apple.com/help/app-store-connect/create-an-app-record/create-and-submit-app-bundles)
- [Using App Store Connect API — fastlane docs](https://docs.fastlane.tools/app-store-connect-api/)
- [Environment variables / dotenv — fastlane docs](https://docs.fastlane.tools/advanced/other/)
