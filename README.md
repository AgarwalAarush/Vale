# Vale

A native Mac companion for writing, coding, documents, and talking through what is on your screen. Open it and type. General chat is the default; Learn and step-by-step help are optional. One native workspace keeps conversation, files and notes together.

<img src="docs/images/vale-workspace-light.png" alt="Vale single-window workspace with chat history, conversation and composer" width="1000">

The screenshot shows the actual native app with generated public fixtures. Light, dark and system appearances are available. Chat, history, Settings, files and Notes share one resizable workspace.

## Work with your screen

1. Choose **Share a window** and select exactly the window you want to discuss. Preview it whenever you need to check the scope.
2. Turn on **Live** to refresh that window locally about every two seconds. It keeps one current preview in memory. Images are sent when you ask a question or request a guide step, not on every refresh.
3. Type a question, choose **Talk**, or opt in to **Conversation**. Conversation takes turns: listen, answer, then listen again. Tap the microphone to interrupt an answer. Typing stops dictation and ends hands-free turn-taking.
4. Choose Learn, then **Chat actions → Start step-by-step guide** for a short guide. Back/Next asks for help at that step with fresh context. Progress is saved with the chat; the assistant never treats navigation as proof that an action happened.
5. **Pause** or **Escape** stops voice, pending replies, sharing, and highlights. A new chat or sleep/lock also clears live context. Resume does not restart the microphone or sharing automatically.

The selected window is the capture boundary, including whichever page is visible inside it. There is no automatic frontmost-window selection, full-display fallback, or continuous cloud video transmission. If the window changes while an answer is being prepared, the answer is marked and its point/guide is withheld; use Refresh for the current view. Missing geometry prevents pointing with a visible explanation. Hidden windows stop capture; a covered highlight is suppressed with visible feedback.

The 1.3.1 candidate uses **Continue with ChatGPT** in your browser and your eligible ChatGPT plan. It does not require the Codex CLI. Vale keeps its connection in a separate protected Keychain namespace. Apple provides dictation and speech. Voice is interruption-safe turn-taking with final provider replies. It is not network streaming or full-duplex audio. No paid API fallback or new service is configured.

## Everyday use

Control–Option–Space focuses the same workspace. Return sends, Shift–Return inserts a newline, Command–N starts a chat, and Command–Comma opens Settings in place. Resize normally or collapse history for more room. A shortcut conflict is reported rather than silently cleared.

Add images, PDFs, UTF-8 text, or code through **+**, drop, or paste. Up to eight files/chat, 25 MB each. Click to preview and × to remove. Uploaded files stay with messages; screen captures and microphone recordings are not saved in chat history.

History opens chats directly and supports search, rename, Markdown export and confirmed Forget. The details button opens Notes or files; Back returns to the same draft. Forget purges that chat from both the active library and the legacy migration backup while keeping unrelated chats. Deletion failures retain a retryable chat/attachment and show an error; Retry Forget finishes the operation when the failure is resolved. Open previews close when their files are forgotten; sharing previews close on stop.

Long conversations show a context notice: recent messages/excerpts are sent, while the full saved history remains available. The globe exposes optional per-chat Web search and its availability notice. Availability depends on your ChatGPT account, workspace and selected model; a URL alone is not proof that search ran. Genuine direct-provider Web verification remains pending. Voice settings provide language, system voice, speed, and silence timing.

## Build and verify

macOS 14+ and Command Line Tools with a macOS 15.2+ SDK (verified with Swift 6.2.4) are required to build. To receive replies, connect an eligible ChatGPT account in Vale. No API key or Codex installation is required. Pointing geometry requires macOS 15.2+. SwiftPM resolves the pinned official Sparkle 2.10.0 framework.

```sh
scripts/build.sh
VALE_ARCH=universal scripts/verify.sh --integration --repeat
python3 scripts/package-release.py
```

Tests use isolated generated files and labeled synthetic capture/voice adapters. The optional provider integration asks the service through Vale’s own ChatGPT connection using public image/PDF/text fixtures and a synthetic selected-window image. This requires personal browser consent first; JWT/SSE fixtures do not establish genuine sign-in or inference. It does not request hardware consent or alter real chats. See [verification](docs/verification.md) for exactly what is exercised and still pending.

The local app is ad-hoc signed, not notarized. The [published 1.3.0 bootstrap](https://github.com/AgarwalAarush/Vale/releases/tag/v1.3.0) embeds a trusted public key and signed HTTPS update source, with automatic checks and downloads enabled by default and editable in Settings. Its anonymous signed downloads and an actual configured Sparkle check against the live feed have been verified. The 1.3.1 candidate retains this update channel and replaces the bootstrap’s CLI connection with direct ChatGPT sign-in; genuine OAuth/inference acceptance remains pending. The previous unconfigured build needs one manual replacement. See [update configuration and delivery evidence](docs/updates.md); packaging is separate from publication and installation. Laptop installation, Apple Silicon runtime, and real hardware QA remain pending. No notch integration, persistent agents, routines, connectors, or autonomous computer actions are included.

## Working on Vale

Start with [AGENTS.md](AGENTS.md), [architecture](docs/architecture.md), and the [development roadmap](docs/roadmap.md). Public source lives at [AgarwalAarush/Vale](https://github.com/AgarwalAarush/Vale).

The app bundle is `Vale.app`. Swift targets/executable (`Lilt`, `LiltCore`, `LiltCoreChecks`), bundle ID (`local.lilt.companion`), saved preference keys, and `Application Support/Lilt` intentionally retain their legacy names so existing chats and permissions stay compatible. Lilt remains the assistant persona.
