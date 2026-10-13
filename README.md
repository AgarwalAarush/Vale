# Mythos

A native Mac companion for writing, planning, coding, images, documents, and everyday questions. Open it and type. Learn with hints is an optional mode; chats are untimed unless you choose a focus timer.

## Use it

Open `dist/Mythos.app`. Control–Option–Space brings up the compact composer anywhere. Return sends, Shift–Return adds a line, and Escape stops a response or voice playback. Use **New chat** or Command–N for a fresh conversation.

- Add images, PDFs, UTF-8 text, or code with **+**, drag and drop, or paste copied files/images. Up to eight files per chat, 25 MB each. Click a file to preview it; remove it with its × button.
- Use the globe to enable web search for that chat. Search is off by default; web answers include direct source links.
- Choose **Share a window** for current screen context. Sharing and Talk are optional and require macOS permission when first used. Talk transcribes one spoken turn; replies can be read aloud.
- **Chat history** lets you search messages, notes, and filenames; rename, continue, export, or forget a chat. Drafts and uploads stay with the conversation. Forget removes the chat and its managed files.
- The **Ask** menu switches to **Learn** when you want hints. A timer is available under More → Focus timer.

Uses the official Codex CLI's existing ChatGPT sign-in. No API billing fallback is configured. If the CLI is missing or signed out, Settings explains how to connect it. The assistant is Lilt; the app is Mythos.

## Build and verify

macOS 14+, Swift 5.9+ Command Line Tools, and an existing Codex CLI are required. SwiftPM downloads the pinned official Sparkle 2.10.0 framework on first build.

```sh
scripts/build.sh                       # this Mac's architecture
MYTHOS_ARCH=universal scripts/build.sh # Intel + Apple Silicon
scripts/verify.sh                      # core checks + real native UI
scripts/verify.sh --integration        # also real ChatGPT uploads + web search
python3 scripts/package-release.py    # package verified universal app and source
```

`verify.sh` uses isolated test libraries and public generated fixtures. It does not change your saved chats or request microphone/screen permissions. Native screenshots are in `artifacts/`.

The local app is ad-hoc signed, not notarized. `scripts/install.sh` installs a fresh copy without replacing an existing Mythos app. Installation on the user's laptop remains pending screenshot delivery and local verification.

See [release status](docs/status.md), [verification](docs/verification.md), [architecture](docs/architecture.md), and [updates](docs/updates.md).
