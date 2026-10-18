# Vale
Vale is a general-purpose native macOS companion. Learning is an optional mode. Preserve legacy Lilt storage and bundle identifiers. The assistant persona is not renamed by product branding. Preserve the original dark floating capsule and coach visual system. Typing is a first-class feature, voice optional. Avoid full-height chat sidebars and generic dashboards.

Build: `scripts/build.sh`. Core tests: `swift run --disable-sandbox LiltCoreChecks`. Native UI checks: `scripts/verify.sh` (added with app harness). Render and inspect screenshots of the actual AppKit/SwiftUI views, not a browser reconstruction.

Never log credentials, microphone audio, or screenshots. No automatic window selection, startup microphone activation, paid fallback, or launch-on-login registration. Publishing source or binaries requires an explicit user request. Store sessions atomically and preserve drafts. Every async completion must validate its session and request identity. Screen context must be refreshed at request time. Only explicitly enabled web search may be exposed to the model; no command, file, app, or browser tools. Uploaded files are deliberately retained with chats; captured screenshots and microphone audio are not.

Live context is explicit opt-in on one selected window, refreshed locally with one bounded RAM preview; send only on a question/guide action. Conversation may rearm the microphone only after explicit opt-in and the current playback completes. Pause, Escape, sleep/lock, session changes and errors stop it. Do not call this full-duplex or network streaming. Forget must purge target content from the legacy backup and report deletion failures with retryable state. Synthetic capture/voice tests must stay labeled and never imply real hardware consent coverage.

## Cursor Cloud specific instructions

Cloud Agents run on Linux. `scripts/build.sh`, `scripts/verify.sh`, and `Vale.app` need macOS (AppKit, SwiftUI, and codesign). Render native views on macOS.

The environment installs Swift 6.1.2. Linux Foundation already provides `CGRect`; the install also adds a `CoreGraphics` module that re-exports Foundation so `LiltCore` can compile. Use that module for LiltCore geometry.

On Linux, run `swift run --disable-sandbox LiltCoreChecks` (28 core checks) and `python3 scripts/check-update-config.py` (updater fixtures). Both use generated files. They do not read credentials or real chats.
