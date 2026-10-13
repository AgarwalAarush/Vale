# Architecture

- AppKit controls actual windows, menu bar, global hotkey, visual material, and overlays. SwiftUI supplies the compact capsule, coach, onboarding, library, and settings. An AppKit NSTextView handles Return / Shift–Return and input-method composition.
- AppModel owns active session state. Every asynchronous capture/provider completion validates its request and session identity. Only the model mutates persisted session data.
- TutorProvider starts the official Codex CLI with saved ChatGPT auth with forced ChatGPT login method, isolated ephemeral working directory, read-only sandbox, ignored user configuration/rules, and explicitly disabled integrations/tools. Prompts enter through stdin. Structured text + optional rectangle leave through a JSON schema. No credentials are read by Lilt.
- WindowContext uses the system single-window sharing picker and SCScreenshotManager, never a whole-display fallback. Context snapshots are compressed/resized to a bounded PNG. While a pointing highlight is visible, brief local capture checks clear it if the content scrolls or changes. Temporary request directories are removed after completion or cancellation. Screenshots and audio are not part of the session store.
- VoiceController uses Apple Speech + AVAudioEngine. When on-device recognition is supported it is required; otherwise Apple speech may use its service, as disclosed in Settings and the native permission prompt. AVSpeechSynthesizer supplies optional speech playback. This is turn-based voice, not a paid Realtime integration.
- LiltCore owns Codable models, structured reply validation, prompt composition, and atomic session storage. Core tests cover preservation, corruption, permissions, spoiler policy, and pointing bounds.
- The native harness launches the same app and views used by the product, renders PNGs, and exercises session transitions. The integration harness also asks the real signed-in provider. No browser imitation is used for native UI verification.

## Primary references

- https://learn.chatgpt.com/docs/non-interactive-mode
- https://learn.chatgpt.com/docs/config-file/config-reference
- https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- https://developer.apple.com/documentation/screencapturekit/sccontentsharingpickerobserver
- https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition
