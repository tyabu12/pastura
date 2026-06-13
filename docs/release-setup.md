# Release Setup (maintainers)

What it takes to make a machine able to cut a Pastura TestFlight release.
Once set up, releasing is just the [`/release`](../.claude/skills/release/SKILL.md)
skill, which drives [`scripts/release.sh`](../scripts/release.sh) per
[ADR-014](decisions/ADR-014.md).

There are **two** kinds of setup — don't confuse them:

- **[Part A — Per-machine setup](#part-a--per-machine-setup)**: what you do on
  **every new Mac**. This is the common path (new laptop, fresh OS install).
- **[Part B — Account-level setup](#part-b--account-level-setup-once-ever)**:
  done **once ever** for the whole project (Bundle ID, app record, API key).
  Already completed — kept here for reference, key rotation, or a new account.

> 🔐 The App Store Connect API key (`.p8`) is a credential. Never paste its
> contents into chat, commits, or any in-repo file. It lives outside the repo;
> only its file path is referenced. See [§ Security](#security).

---

## Part A — Per-machine setup

Do this on each new Mac. Assumes Part B is already done, so you have: the saved
`AuthKey_XXXXXXXXXX.p8` file, its **Key ID**, and the **Issuer ID**. The Apple
Developer Program membership is active.

### 1. Clone the repo

```bash
git clone git@github.com:tyabu12/pastura.git ~/Work/pastura
cd ~/Work/pastura
```

### 2. Put the API key on this machine

Copy the `.p8` you saved in Part B to this Mac and lock it down (keep it
**outside** the repo):

```bash
mkdir -p ~/.appstoreconnect/private_keys
chmod 700 ~/.appstoreconnect/private_keys          # dir: owner-only (needs the x bit)
cp /path/to/your/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8   # file: rw, owner-only
```

(`600` is for the **file**; a directory needs its execute bit to be
traversable, so lock the directory with `700`, not `600`.)

The same `.p8` is reused across machines — you do **not** generate a new key
per machine (only on leak/loss; see Part B).

### 3. Create `fastlane/.env`

Project-scoped, gitignored, auto-loaded by fastlane (no `~/.zshrc` exports):

```bash
cp fastlane/.env.example fastlane/.env
```

Edit `fastlane/.env` with your values (absolute path — dotenv does not expand
`~`/`$HOME`):

```
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=12a3b456-7890-....
ASC_KEY_PATH=/Users/<you>/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Confirm git will never see it:

```bash
git check-ignore fastlane/.env    # → prints "fastlane/.env" (ignored)
```

### 4. Set up code signing in Xcode

`scripts/release.sh` archives headlessly, which needs a distribution
certificate + App Store provisioning profile present on **this** machine.

1. Open `Pastura/Pastura.xcodeproj`.
2. **Xcode → Settings → Accounts**: sign in with an Apple ID on team
   `52G26234A3`.
3. Run destination → **Any iOS Device (arm64)** (Archive is disabled for
   simulators).
4. **Product → Archive**. Automatic signing provisions the distribution
   certificate + profile on this machine. When the Organizer opens you can
   stop — `/release` handles real uploads.

> A distribution cert's private key lives in the Mac's keychain, so a new
> machine needs its own. Letting automatic signing create one (above) is
> simplest. If you'd rather reuse the existing cert, export it as a `.p12`
> (Keychain Access → your "Apple Distribution" cert → Export) from the old
> Mac and import it on the new one before archiving.

### 5. Install fastlane

```bash
bundle install            # generates Gemfile.lock (recommend committing it)
```

If `bundle install` fails on the system Ruby (2.6.x), install a newer Ruby
(`brew install ruby`) and re-run.

### 6. Verify

Confirm the key authenticates, with no side effects (returns `0` for a
brand-new app):

```bash
TF_BUILD_OUT=/tmp/tf bundle exec fastlane ios latest_tf_build version:1.0
cat /tmp/tf               # 0 → the key works and fastlane read fastlane/.env
```

### 7. Release

```
/release
```

The skill proposes the version bump, synthesizes the "What to Test" notes for
your review, runs `scripts/release.sh --dry-run` to show the preflight, and —
after a mandatory confirmation — archives, uploads to TestFlight, and tags.

---

## Part B — Account-level setup (once ever)

These are done **once for the whole project**, not per machine. **Already
completed** — this section is reference for key rotation or a fresh account.

### B1. Register the Bundle ID

1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles**
2. **Identifiers** → **＋** → **App IDs** → **App**
3. **Description**: `Pastura` · **Bundle ID**: **Explicit** → `app.pastura.Pastura`
4. Defaults → **Continue** → **Register**

### B2. Create the App Store Connect app record

1. https://appstoreconnect.apple.com → **Apps** → **＋** → **New App**
2. **Platforms**: iOS · **Bundle ID**: `app.pastura.Pastura` · **SKU**:
   `pastura-ios` · **User Access**: Full Access
3. **Name**: `Pastura - Local LLMs simulator` — the store Name must be globally
   unique; plain "Pastura" was already taken. The home-screen name stays
   **Pastura** (from `CFBundleName`/`CFBundleDisplayName`, independent of the
   store Name).
4. **Create**

> The App Store **subtitle** (`Like stargazing, but for LLMs`) is part of the
> version's store listing, set later at App Store submission (Phase 3) — not at
> record creation, and not needed for TestFlight.

### B3. Generate the API key (`.p8`)

1. App Store Connect → **Users and Access** → **Integrations** →
   **App Store Connect API** → **Team Keys** → **Generate API Key (＋)**
2. **Name**: `pastura-release` · **Access**: **App Manager** → **Generate**
3. **Download** `AuthKey_XXXXXXXXXX.p8`. ⚠️ **Downloadable only once** — save it
   somewhere durable; this is the file you copy onto each machine in
   [Part A step 2](#2-put-the-api-key-on-this-machine).
4. Note the **Key ID** (10 chars) and **Issuer ID** (UUID above the keys table).

---

## Security

- The `.p8` is the only real secret. It stays at
  `~/.appstoreconnect/private_keys/` (outside the repo), `chmod 600`. Only its
  path is referenced from `fastlane/.env`.
- `fastlane/.env` is gitignored and holds identifiers only; `*.p8` is globally
  gitignored and `scripts/p8-precommit-gate.sh` refuses any staged `.p8`.
- **If the key leaks** (committed, shared, lost): revoke it immediately in
  App Store Connect → Users and Access → Integrations → App Store Connect API →
  (select the key) → **Revoke**, then regenerate (Part B3) and update
  `fastlane/.env` on every machine. See the `/release` skill's revocation
  section and [`docs/security/release-checklist.md`](security/release-checklist.md) § 4.

## Sources

- [App Store Connect API — Apple Developer Help](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Create an app record — Apple Developer Help](https://developer.apple.com/help/app-store-connect/create-an-app-record/create-and-submit-app-bundles)
- [Using App Store Connect API — fastlane docs](https://docs.fastlane.tools/app-store-connect-api/)
- [Environment variables / dotenv — fastlane docs](https://docs.fastlane.tools/advanced/other/)
