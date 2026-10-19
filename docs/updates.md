# Built-in updates

Current handoff, rechecked 2026-10-19: the Vale 1.2.3 build 6 DMG does **not** update itself. Its payload is unchanged from the verified private handoff. The source, built app, staged app and ZIP all have no update feed/public verification key, with automatic checks, downloads and installation disabled. The configured runtime implementation is also manual-check-only; supplying a feed alone would not add automatic updates. Evidence: `artifacts/update-status-2026-10-19.json`. Laptop installation and its current version remain unverified from this host.

The updater is implemented in `Sources/Lilt/Updates.swift`, backed by the embedded official Sparkle 2.10.0 framework. Settings and the app menu expose **Check for Updates**. The distributed local build intentionally has no production feed or public key; its check action is disabled and the engine does not start.

## Enforced configuration

- HTTPS feed without embedded credentials or fragments.
- Existing 32-byte Ed25519 public key, encoded as base64.
- `SURequireSignedFeed=true` and `SUVerifyUpdateBeforeExtraction=true`.
- HTTPS release archives on the feed's same host and port. The primary enclosure and every delta enclosure on that item must match. The URL Sparkle is about to download, including a full-archive fallback after a delta, is checked again; a disallowed URL is cleared so Sparkle aborts before connecting. Sparkle's downloader can still follow an HTTP redirect, so signature verification before extraction stays required.
- Manual checks, without automatic checks, downloads, or installation.
- Sparkle handles signature verification, update selection, download, and installation; the app does not implement an unchecked custom downloader.

The build accepts existing public configuration through `VALE_UPDATE_FEED_URL` and `VALE_UPDATE_PUBLIC_KEY`. `scripts/configure-updates.py` validates these and embeds them before signing. It never creates a key, reads a private signing key, publishes a feed, or uploads an artifact. Never put a private key in these variables.

## Local verification versus production rollout

Core checks cover invalid feeds, malformed keys, missing verification gates, and seven archive URL fixtures in `Tests/LiltCoreTests/Fixtures/update-policy.json`. The native harness verifies that the default release is inactive. Bundle checks verify the embedded framework and strict code signature. These checks do not establish that a live signed update can download/install: there is no configured production feed or signed update fixture.

To activate production updates, provide an authorized private HTTPS delivery source, the existing Ed25519 public key and an established private-key signing workflow, and Developer ID signing/notarization for the app. Feed XML and release archives must be signed by that trusted workflow. Private hosting must be accessible to Sparkle without embedded URL credentials; any authentication integration needs a concrete delivery design. A signed, notarized next-version update must then be tested from the installed previous version, including tampered-feed/archive rejection and rollback/recovery behavior.

No new signing keys, Developer ID credentials, hosting, public release, or persistent access were created. No Gatekeeper or denied computer-use action was bypassed.
