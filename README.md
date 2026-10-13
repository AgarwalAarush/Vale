# Lilt

A native Mac learning companion. Keep working in your browser, editor, or paper reader. Type a question, talk it through, or choose a window for context. Lilt gives one useful question or hint at a time.

## Use it

Open `dist/Lilt.app`, choose a topic, and start learning. **Control–Option–Space** opens the coach from anywhere. Lilt also lives in the menu bar.

- **Type:** Return sends. Shift–Return adds a line. Paste code normally.
- **Talk:** choose the microphone, speak your question, and pause briefly. Lilt transcribes it and answers aloud. Choose the microphone again or press Escape to interrupt. Read typed replies aloud is optional.
- **Share:** choose “Share a window” and select one window in the native macOS picker. Lilt refreshes context when you ask. Click the shared window name for a preview; Stop sharing clears it.
- **Hints:** ask for Hint, or Point it out with a shared window. A full walkthrough requires an explicit confirmation from the coach menu.
- **Pause:** stops voice, cancels the current request, clears sharing and highlights, and freezes the timer. Resume keeps your conversation and draft. Choose a window again when ready.
- **Finish:** Complete session opens your review. Write one takeaway in your own words. Continue, export Markdown notes, or Forget from the session menu.

Text works immediately through the official Codex CLI already signed in on this Mac. Microphone/speech access and the system window picker require your own macOS consent when first used. No API key or separate paid voice service is needed by this implementation. Codex requests use the signed-in account’s available usage.

Your conversations and takeaways are stored in `~/Library/Application Support/Lilt/sessions.json`. Screenshots are temporary and removed after requests; microphone recordings are not saved by Lilt. Apple speech may use its speech service if on-device recognition is unavailable. Selected screen context and conversation are sent to the tutor when you ask.

## Develop and verify

Requires macOS 14 or newer, Apple Command Line Tools with Swift 5.9+, and the official signed-in Codex CLI. Pointing metadata requires macOS 15.2+. This release was built and verified on macOS 15.7.9 with Swift 6.1.2 for Intel.

```sh
scripts/build.sh
scripts/verify.sh
scripts/verify.sh --integration
```

The build has no third-party package dependencies. The core test runner avoids requiring the full Xcode IDE. Verification produces screenshots of the actual native views and a JSON result report in `artifacts/`. Integration checks send two small requests to your signed-in provider: text and an image of the app’s own test conversation. Test data uses an isolated library; it does not change your real sessions.

`dist/Lilt.app` is ad-hoc signed for local use. It is not notarized for public distribution. `scripts/install.sh` installs a fresh copy into your user Applications folder without replacing an existing app.

See [architecture](docs/architecture.md), [requirements](docs/requirements.md), and [verification](docs/verification.md) for scope and evidence.
