# Release status

Mythos 1.1.0 (build 2) is a completed local general-assistant release, built for Intel and Apple Silicon.

The app opens straight into an untimed chat. Typing, multiple image/PDF/text/code uploads, previews, retained drafts/files, optional web search with sources, searchable history, rename, notes, export, and Forget are implemented. Learn and focus timers are optional. The original dark floating UI is retained. Mythos branding preserves the Lilt assistant persona, bundle identity, saved chats, and settings; legacy migration saves an exact backup.

The universal app passes 15 core checks, five build-configuration checks, 21 native flow checks, and 26 live integration checks on Intel. Actual ChatGPT multi-file responses and real web-search events are verified. Native screenshots were inspected. See verification.md for exact evidence and limitations.

Sparkle 2.10.0 is implemented and embedded. Its production configuration is inactive pending a private HTTPS release source and existing trusted signing assets. The app is locally ad-hoc signed and not notarized. No feed, credentials, signing keys, or public release were created.

Apple Silicon runtime verification, laptop delivery/installation, first-use microphone/window-sharing consent, and a production signed-update rollout remain separate pending actions. Laptop installation stays paused until the parent confirms screenshots were delivered locally. The old remote Lilt 1.0 installation remains untouched.
