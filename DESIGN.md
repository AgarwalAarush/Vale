---
name: Vale
description: A tiny native Mac companion beside the user's work.
platform: macos
---

# Design System: Vale

## Approved visual authority

The owner selected [Pearl Glass](docs/design/compact-companion-2026-10-20/01-pearl-glass.png)
on2026-10-20: “this one is phenomenal lets build this out”.
Its .png.json sidecar records approval. Pearl supersedes the large workspace
and the coordinator's earlier Lens recommendation.

The three columns show successive Ready, Ask and Answer states of one panel.
The textbook, desktop chrome, monitor bezel, example prose and equation are
contextual illustrations, not shipped UI rasters or answer-correctness claims.
Use native text, symbols and controls. Retain the canonical folded-ribbon V.

## Product and composition

Vale is a shortcut-summoned helper at the top right while the user reads or works.
The working app stays dominant. One physical panel expands left/down around a
fixed top-right anchor. History/settings/files/notes/Learn tools reveal on demand
inside it. Native OS dialogs and click-through pointing feedback retain their
limited existing roles.

| State | Native implementation |
| --- | --- |
| Ready | 300×45pt; V, editable Ask Vale…, microphone, overflow |
| Ask | 320pt wide, at least188pt high; header, optional context/status/files, editor, plus/mic/send |
| Answer | 350pt wide; latest exchange, measured reply viewport up to320pt, follow-up composer |
| History | 400×500pt in the same panel |
| Files/notes/context | 460×540pt in the same panel |
| Settings | 520×610pt in the same panel |
| Bounds | Ordinary height capped650pt; visible-frame inset18pt; fixed composer above scrollable overflow |

All sizes are logical AppKit points and implementation choices. Long content
scrolls; never restore the old740pt minimum or1040pt default. A permanent toolbar,
sidebar, traffic-light titlebar, greeting hero or second assistant workspace
conflicts with the approved composition.

Control–Option–Space explicitly summons on the pointer's display. Ordinary state
changes retain the anchor. The floating panel supports all Spaces/fullscreen
auxiliary behavior; physical display/Space acceptance is separate.

## Material, color and type

NativeCompanionMaterial wraps real NSGlassEffectView regular material on macOS26,
using contentView for stable hosted content. On14/15 it uses active
NSVisualEffectView popover material with behind-window blending. The window is
transparent, rounded and uses a native shadow. Reduce Transparency supplies an
opaque semantic surface. Corners are22.5pt at rest and24pt expanded.

Swift6.2.4 matches the installed Xcode26.2SDK. Explicitly override inherited
SDKROOT, which pointed to an older CLTSDK. This host runs macOS15: compiling
the26path does not verify its optics. In-process native rasters do not reproduce
compositor backdrop blur/shadow exactly.

Use system type and SF Symbols. Current Ready editor12pt, expanded editor14pt,
message prose13pt, header12pt and status/context around11–12pt. Preserve labels,
native hit areas and visible focus. Do not shrink text to force mockup dimensions.

Theme's adaptive source pairs remain: ink #252629/#f0f0ed, muted #67686b/#b0b1b8,
accent #5759c6/#b9bcff, action #28292d/#ecece8, on-action #ffffff/#252629.
Secondary fills are adaptive neutrals; the main shell is a native material.
Avoid nested glass cards, glow and decorative idle waveforms. A200ms shape
transition respects Reduce Motion. Feedback must not shift controls.

## Interaction and retained capabilities

Keep one DraftEditor/NSTextView mounted across states and secondary routes.
Preserve draft ownership, marked text, selection, undo, paste/drop and files.
Covered editors reject focus/send. Return sends only when permitted;
Shift–Return inserts a line. Browser return never sends.

Disconnected drafting/attachments work locally, with one clear connection/retry
action replacing unavailable Send. Busy exposes Stop. Failed questions retain
original retry/file ownership while newer drafts stay unsent. Async imports keep
their originating owner and show accurate status across routes.

Explicitly selected context has an identifying/removable chip, preview and Live
controls. Refresh at request time; send only on an explicit request. Screenshot
and microphone buffers remain transient. Dictation requires explicit activation
and visible status/Stop. Conversation rearming requires opt-in and completed
playback. Pause, Escape, sleep/lock, session changes and errors stop interaction.
Do not call this full-duplex streaming.

Replies provide Copy/read-aloud. Overflow retains new/history/earlier messages,
Learn/hints/guide/walkthrough, timer, notes/files, Web opt-in, Talk/Conversation,
rename/export/Forget, pause/close, settings and updates. Secondary routes provide
Back and applicable Stop/import status.

## Compatibility and acceptance

Preserve local.lilt.companion, legacy storage, chats/drafts/files/settings and the
assistant persona. No startup mic/capture, automatic window selection, paid
fallback, model command/file/app/browser tools, credentials logging or login agent.
Forget still purges target backup content and exposes deletion failures/retry.

The [native product pipeline](docs/design/native-product-pipeline.md) and current
Factory round own checks, actual native visual review, independent review and
delivery. Old large-window results are historical; approved mockups are not
runtime acceptance. Bind complete-panel generated captures to source/executable
hashes. Inspect Ready/Ask/Answer, long replies, combined states, secondary routes,
light/dark and keyboard recovery. Keep raster/injected-event evidence distinct
from compositor, physical accessibility, real voice/screen consent, genuine
ChatGPT, package/feed and target-laptop installation. Preview is not production
readiness.
