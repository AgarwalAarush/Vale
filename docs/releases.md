# Publishing Vale updates

From a clean, committed release branch, run:

```sh
python3 scripts/release.py 1.3.4 --publish
```

This commits the version/build increment, builds both Mac architectures, runs core,
updater configuration and native UI checks once, prepares the app ZIP, installer
ZIP/DMG, source archive, manifest and checksums, then signs the archive and appcast.
It pushes the release branch normally, uploads a GitHub **draft**, downloads and
checks every draft asset, and only then publishes it as the primary latest release.
Finally it downloads every public asset anonymously and checks the live latest feed.
It never force-pushes, pushes main, replaces published assets, installs Vale, captures
personal screen/audio, or performs real-account inference.

The actual remote Git tag is checked independently of draft creation metadata,
including bounded recursive annotated-tag peeling. An existing tag must resolve
to the exact source before draft creation/resume and immediately before promotion.
A tag created only on publication must resolve correctly afterward. Conflicts are
rejected without moving or replacing tags. Origin and the release branch are
checked before expensive building/signing, and checked again before the normal push.

Run `python3 scripts/release.py 1.3.4 --plan` for a read-only pipeline preview.
Use `--prepare-only` instead of `--publish` to stop after local signing. Add
`--notes-file docs/release-notes-1.3.4.md` to supply public release notes. The command
requires macOS, a logged-in GUI session, Xcode/Swift, Git and an authenticated `gh`.
The native checks use generated account/voice/screen fixtures; they do not establish
genuine ChatGPT or physical-device acceptance. The strict independent
`package-release.py` integration gate remains available and unchanged.

Native checks execute a disposable copy with a nonce bundle identifier and a new
ad-hoc signature. Only `CFBundleIdentifier` changes in its plist; the command verifies
identical `__TEXT,__text` instruction sections and the clone's strict signature before
launching it. This keeps ordinary Vale preferences out of the test. The original
production bundle stays unchanged for packaging. The receipt records this isolation
and its distinction from whole-file executable equivalence.

Sparkle Ed25519 signing authenticates the update feed and archive. The default app
build remains ad-hoc signed. This command does **not** establish Apple Developer ID,
notarization or Gatekeeper acceptance. Those are separate distribution credentials
and checks; the receipt keeps them unverified. Normal macOS security remains enabled.

The signing seed defaults to the Git common directory's
`codex-factory/private/vale-updates-v1.key`. It must be an owner-owned regular `0600`
file in an owner-owned `0700` directory, with no symlink components. Alternatively set
`VALE_UPDATE_SIGNING_KEY_FILE` to such a file. Never paste the seed into a command,
environment value, log, repository or chat. Python inspects metadata only; Sparkle's
stock `sign_update --ed-key-file` reads the seed. A separate CryptoKit helper verifies
both signatures with only the pinned public key. `VALE_SPARKLE_TOOLS_DIR` can point
to the directory containing the stock `sign_update` binary when reusing a build.

The command downloads and verifies the current signed production appcast, retains
its old entries, and requires a strictly larger `CFBundleVersion`. New entries use
immutable versioned GitHub archive URLs. No deltas or updater trust policy changes
are introduced. Configured older Vale builds pick up the newer primary release while
open according to their saved preferences; automatic installation normally occurs
on quit. Unconfigured old builds still require a one-time manual replacement.

For an already reviewed immutable build, avoid rebuilding it:

```sh
python3 scripts/release.py 1.3.3 \
  --prepared-assets /absolute/path/to/reviewed-release-assets \
  --notes-file /absolute/path/to/release-notes.md --publish
```

The directory must contain exactly the six original `Vale-VERSION-*` assets. The
command checks every checksum, manifest binding, source archive byte, universal
executable, updater default and strict code signature. App inputs must be unchanged
since the manifest's source commit. It preserves all six reviewed bytes and adds a
signed `appcast.xml`, a current automatic-update receipt, and additional checksums.
Preparation-time preview/unpublished labels inside those original files are
historical; the current release notes and automatic-update receipt supersede only
their delivery status. They do not upgrade unverified product/provider/hardware
claims. A preview tag and its files are never overwritten when publishing the
separate primary release.

Local state and frozen file hashes are saved under the Git common directory's
`codex-factory/releases/vVERSION/`. Retrying the same command resumes an unchanged
draft, verifies existing uploads and avoids duplicate assets. A failed upload or
changed production feed leaves the draft unpublished. A public version is immutable:
after publication, use a new version. If tag or anonymous verification fails after
publication, the command explicitly reports **ALREADY PUBLIC**, the release URL and
the frozen `release-binding.json` path. A promotion command with an unknown remote
outcome reports **PUBLICATION STATUS UNCERTAIN**. Inspect and verify that existing
release before recovery; do not delete, replace or retag public assets. Successful
verification writes `publication.json` under the release's private state directory;
the appcast is verified from the exact supplied assets path, normally `assets/`.
Tool output remains suppressed so signer errors cannot expose private material.

Run `python3 scripts/test-release.py` to exercise the release command's offline
preflight, feed and draft-publication failure boundaries.
