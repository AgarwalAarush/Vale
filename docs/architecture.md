# Architecture

AppKit owns one normal resizable workspace, the menu bar, global shortcut, native text editor and standard dialogs. SwiftUI renders the history rail, conversation, in-window Settings and Notes/files/context inspector. The native editor and transcript stay mounted across secondary routes, preserving drafts and selection. A compact layout presents details with Back; wide layouts place them beside the chat. A temporary click-through pointing annotation is feedback over the selected app. The first screen is general chat; there is no learning setup gate. PRODUCT.md and DESIGN.md define the current product and visual contract.

AppModel owns chats, drafts, mode, upload metadata, explicit search choice, and request state. Capture/provider completions validate request and chat identity. File import finishes into the originating chat, and cleans up imported bytes if that chat has been deleted. Pause, cancel, sleep, and lock stop transient context and voice. Uploaded files remain intentional chat data.

AttachmentStore retains UUID-named files under the legacy application-support directory with private permissions. ImageIO bounds image inputs to 1600 pixels. PDFKit extracts bounded text, or renders the first four scanned pages with a visible context limitation. Request context has a total text/visual budget. PDF preview renders pages with navigation and copyable page text; text previews are bounded. Imported files are reference data and never executed.

ChatGPTAccount owns direct system-browser OAuth, a loopback PKCE/state/nonce callback, issued-client registrations, JWKS/issuer/audience/expiry verification, and eligible ChatGPT plan grants. Credentials use Vale’s separate Keychain namespace, independent of legacy Codex sign-in. Refresh rotation and vault mutations are serialized; each running copy keeps its explicitly selected account when shared records change. Successful rotations are saved before identity lookups, and pending identity validation blocks inference until verified. Temporary lookup failures retain the replacement for recovery/revocation. Sign-out removes local access before remote revocation. TutorProvider discovers eligible models and sends streaming Responses requests with `store:false`. Byte-preserving SSE framing retains event boundaries across LF/CRLF and split UTF-8; only a complete response can become a reply. Explicit per-chat Web may declare the hosted web-search tool; no command, file, app, browser or coding execution tools are exposed, and there is no API-key fallback.

Account connection changes synchronously invalidate both provider and AppModel request identity, cancel preprocessing, stop voice/sharing and preserve an interrupted question for retry. A late answer cannot cross an account switch. Generated protocol/lifecycle checks are separate from genuine OAuth and inference acceptance.

WindowContext uses ScreenCaptureKit's single-window system picker and fresh SCScreenshotManager captures. There is no display fallback. Pointing requires bounded coordinates, matching generation, identical fresh pixels, and unchanged geometry; local checks clear highlights when content changes. On-screen metadata is required before capture. Front-to-back window bounds conservatively reject a highlight covered by another visible window; unknown bounds fail closed, transparent windows are ignored, and the annotation itself is excluded from subsequent checks. This reads window metadata, not other-window pixels. Screen images and microphone audio are not in the chat store.

VoiceController uses Apple Speech and AVAudioEngine only after Talk. On-device recognition is required when supported; otherwise Apple may use its speech service, as disclosed in Settings. AVSpeechSynthesizer provides optional playback. Voice is turn based.

LiltCore provides backward-compatible Codable models, structured replies, prompt policy, search, atomic storage, and updater configuration policy. Legacy records without a mode remain Learn chats, with their IDs/drafts intact; the original JSON is backed up before rewrite. The Vale rename preserves `local.lilt.companion`, preference keys, and `Application Support/Lilt`.

UpdateController embeds the pinned official Sparkle 2.10.0 framework. Without an existing HTTPS feed and trusted public key, no updater instance starts or checks the network. Configured builds require signed feeds with strict failure expiration zero, signature verification before archive extraction, and a same-origin HTTPS policy for the primary archive, deltas and initial download request. Automatic checks/downloads default on; stored Sparkle preferences remain authoritative and are editable in Settings. The manual action remains available with automatic checks off. Native fixture modes disable the production backend. See updates.md for configuration, signing and the separate publication boundary.

The native harness runs the same NSWindows and views as the product with isolated generated fixtures. It captures app-owned views, exercises transitions, and optionally sends real multi-image/PDF/text and web requests. It does not imitate the interface in a browser or bypass screen/microphone consent.

## Primary references

- [Direct ChatGPT sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Profiles and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [Eligible models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [ScreenCaptureKit screenshots](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [Apple on-device speech recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [Sparkle setup and signed updates](https://sparkle-project.org/documentation/)
- [Sparkle programmatic setup](https://sparkle-project.github.io/documentation/programmatic-setup/)
- [Pinned Sparkle 2.10.0 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)

## 1.2 interaction update

WindowContext coalesces capture requests behind a bounded cancellation-aware deadline. The system filter is one explicitly selected window. Live samples locally, keeps one preview in RAM, and clears it on stop/failure; on-demand requests do not keep preview pixels. Request-time and post-reply captures compare scope, pixels and geometry. ScreenEvidence separately permits text freshness without older-OS geometry while requiring finite known geometry and recent matching evidence for a point. Stale replies are labeled; new stale guides and points are suppressed.

VoiceController separates recognition/playback generations and exposes natural playback completion. AppModel rearms recognition only for the current explicitly opted-in conversation, after playback, with chat/request identity checks. Interruption, typing, errors, stop/pause, sleep and session changes cancel pending rearm. Test-only adapters bypass physical audio/capture while using those same state transitions. These adapters require explicit harness launch arguments.

GuidePlan/GuideProgress validate bounded plans and persist navigation; user-triggered navigation requests a fresh frame. ConversationWindow selects bounded recent excerpts and supplies a visible/prompted limit notice. SessionStore.forget filters only the target from the legacy backup before saving the active library. AttachmentStore throws unlink failures; AppModel retains retryable metadata and reports partial deletion. AppController releases preview contents on close, sharing reset or managed-file removal.
