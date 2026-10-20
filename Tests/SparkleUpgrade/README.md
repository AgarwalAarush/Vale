# Isolated Sparkle 2.10 integration verification

This directory contains reviewable integration tooling. Each run explicitly prepares and launches only a disposable fixture. It is independent of Vale source and never opens, quits, replaces, or reads data from an installed Vale app.

## Gates and exact side effects

1. Read `scripts/verify-sparkle-upgrade.py`, `FixtureApp.m`, and `make-test-keys.swift` first. `python3 scripts/verify-sparkle-upgrade.py plan` has no side effects.
2. After the coordinator authorizes disposable file keys and compilation, `prepare --authorize-ephemeral-keys --case CASE` creates one new mode-0700 `/private/tmp/vale-sparkle-fixture.*` directory. Only that directory receives private seeds (0600), fixture apps, code-signatures, archives, signed appcast, logs and receipts. Cases are `valid`, `feed-tamper`, and `archive-tamper`; each gets a fresh bundle ID, key, port and defaults domain. No Keychain API/tool is used. The SDK's `sign_update --ed-key-file PATH` reads a base64 32-byte seed; `generate_keys` is deliberately unused because its normal custody is persistent Keychain.
3. `prepare` runs the stock signature verifier on valid bytes and the selected tampered bytes. This proves signing/verifier behavior only. It does not run Sparkle's downloader/installer or prove automatic application behavior.
4. After explicit coordinator inspection/authorization of GUI and per-fixture state, `run --authorize-fixture-gui-cache RUN_ROOT` serves only `127.0.0.1`, launches only the exact app inside that root, and waits at most 120 seconds. **Real Sparkle writes nonce-scoped preferences/caches under the current user's Library.** Its SDK has no public `/tmp` cache-root switch. The unique main bundle ID isolates these from Vale/global preferences (do not set SUDefaultsDomain to that same ID: macOS rejects an explicit suite equal to the app domain), but these OS-managed writes mean the real run is not strictly `/tmp`-only. No persistent Keychain/security/trust changes, no sudo, no force-kill, no installed-app mutation. The fixture normally terminates itself and has a 90-second self-timeout.
5. `valid` requires an automatic startup background feed/archive request, `willInstallUpdateOnQuit`, version-2 executable hash installed at the old fixture path, and receipts from the **compiled version-2 binary** after relaunch proving restoration of generated draft, note, attachment and preference fixtures. Default mode is ordinary quit followed by an explicitly labeled runner relaunch; `--mode relaunch` tests Sparkle's immediate installation/relaunch handler instead. Automatic defaults come from Info.plist; fixture code never forces runtime settings true or calls manual/background check APIs.
6. `feed-tamper` requires a cryptographic SDK rejection, no archive fetch, and unchanged old executable. `archive-tamper` keeps a valid signed feed describing the modified archive's actual length but the original archive signature; it requires download then a cryptographic SDK rejection and unchanged old executable. Incidental HTTP/configuration/extraction errors do not pass. Receipts retain error domain/code chains and a signature-related boolean, without copying full arbitrary error strings.

## Preconditions and evidence boundary

- Stock macOS Python 3 is used only to coordinate this developer prototype (not a laptop installer dependency), with Swift/CryptoKit, clang/CLT, codesign, ditto and the existing Sparkle 2.10 framework/tools. No software is installed.
- GUI login/session with LaunchServices is required for `run`. App names/IDs are unique. The fixture creates only its own generated draft, note, attachment and defaults values to test preservation; it reads no Vale/user chats or files and has no microphone/capture, provider or credentials.
- The fixture uses test-only loopback HTTP and a bundle-local ATS allowance. Production `UpdateConfiguration` must continue requiring HTTPS and same-origin enclosure URLs. This test cannot establish production HTTPS/GitHub redirects, published-byte availability, notarization, Apple Silicon runtime or user-laptop acceptance.
- The fixture is ad-hoc signed without Hardened Runtime. The bundled SDK is retained; the fixture host is independently signed after assembly. This is supported EdDSA/ad-hoc update evidence, not Developer ID/notarization evidence.
- Do not run multiple cases against a shared run root or reuse an ID. If a test hangs, inspect the nonce receipt and quit only that fixture through its own UI or exact NSRunningApplication bundle URL. This tooling never issues process-wide termination.
- Keep all prepared run roots until the coordinator reviews receipts. Private seeds are disposable test secrets: never attach them to evidence, version control, source archives or public releases. APFS removal is not guaranteed physical secure erasure; do not use production seeds in this fixture.

## Production key custody

The coordinator created a dedicated persistent production seed in the original repository's git common directory at `codex-factory/private/vale-updates-v1.key` (directory 0700; file 0600), outside every Factory source worktree and tracked tree. Resolve the original git common directory explicitly rather than appending `.git` to a worktree path. Refuse symlinked/private parent paths, group/other access, non-owner files and accidental overwrite. The fixture tooling never reads or uses that production key. **Do not use disposable fixture keys for production.**

Keep only the derived public base64 key in source/configuration. Every production signing command must use `--ed-key-file ABSOLUTE_PRIVATE_PATH`; omission silently falls back to Keychain. Do not place private bytes in command arguments/environment, stdout, logs, evidence, staging directories, archives or source copies. The protected local file is currently the sole copy; no backup has been made. Future custody/backup decisions remain with the owner and coordinator rather than this test tooling.

A configured private candidate can be assembled before publication: real public key, pinned GitHub HTTPS release-feed URL, strict signed-feed expiration zero, automatic defaults, signed archive, appcast and checksums. This neither publishes the feed nor enables the existing unconfigured build. Stage exact reviewed immutable bytes. Publication remains a separate final action requiring explicit authorization; then anonymously fetch and verify feed/archive and exercise a real signed upgrade through the live HTTPS source. One manual bootstrap install remains necessary for previously unconfigured Vale builds.

## Commands, to run only after the corresponding gate

```sh
python3 scripts/verify-sparkle-upgrade.py plan
python3 scripts/verify-sparkle-upgrade.py prepare --authorize-ephemeral-keys --case valid
python3 scripts/verify-sparkle-upgrade.py run --authorize-fixture-gui-cache /private/tmp/vale-sparkle-fixture.RETURNED_ROOT
```

Repeat `prepare` and `run` independently for `feed-tamper`, `archive-tamper`, and optional valid `--mode relaunch`. Review JSON evidence before claiming any layer passed. Sources: https://sparkle-project.org/documentation/ , https://sparkle-project.org/documentation/customization/ , https://sparkle-project.org/documentation/publishing/ .
