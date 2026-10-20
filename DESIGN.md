---
name: Vale
description: A compact native Mac conversation workspace for reading, writing and optional contextual help.
colors:
  ink-light: "#252629"
  ink-dark: "#f0f0ed"
  muted-light: "#67686b"
  muted-dark: "#b0b1b8"
  accent-light: "#5759c6"
  accent-dark: "#b9bcff"
  line-light: "#ddddd6"
  line-dark: "#363840"
  background-light: "#f7f6f2"
  background-dark: "#18191d"
  rail-light: "#eeede8"
  rail-dark: "#141519"
  fill-light: "#eeede8"
  fill-dark: "#292b32"
  fill-raised-light: "#ffffff"
  fill-raised-dark: "#22242a"
  fill-pressed-light: "#e2e1da"
  fill-pressed-dark: "#363840"
  action-light: "#28292d"
  action-dark: "#ecece8"
  on-action-light: "#ffffff"
  on-action-dark: "#252629"
  warning-light: "#825010"
  warning-dark: "#ecc48a"
typography:
  body:
    fontFamily: "macOS system via NSFont.systemFont / Font.system"
    fontSize: "15pt"
    fontWeight: 400
  navigation:
    fontFamily: "macOS system via Font.system"
    fontSize: "13pt"
    fontWeight: 400
  metadata:
    fontFamily: "macOS system via Font.system"
    fontSize: "12pt"
    fontWeight: 400
  label:
    fontFamily: "macOS system via Font.system"
    fontSize: "12pt"
    fontWeight: 500
  panel-title:
    fontFamily: "macOS system via Font.system"
    fontSize: "22pt"
    fontWeight: 500
  code:
    fontFamily: "macOS system monospaced via Font.system(design: .monospaced)"
    fontSize: "13pt"
rounded:
  search: "6pt"
  control: "8pt"
  composer: "10pt"
spacing:
  compact: "4pt"
  small: "8pt"
  inset: "10pt"
  medium: "12pt"
  section: "16pt"
  bottom: "20pt"
  gutter: "24pt"
components:
  composer:
    rounded: "{rounded.composer}"
    padding: "{spacing.inset}"
  history-search:
    typography: "{typography.metadata}"
    rounded: "{rounded.search}"
    padding: "6pt 7pt"
  quiet-field:
    rounded: "{rounded.control}"
    padding: "8pt 10pt"
  quiet-button:
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "8pt 12pt"
  icon-button:
    rounded: "{rounded.control}"
    width: "30pt"
    height: "30pt"
---

# Design System: Vale

## Overview

**Creative North Star: "A quiet Mac conversation workspace"**

Reading and writing lead; history and contextual tools sit beside the task when space permits. This is a recurring native desktop tool in Impeccable Operate mode, built with AppKit and SwiftUI for macOS 14 or later. Native window behavior, familiar controls and precise task hierarchy govern the composition. The folded-ribbon V remains the identity asset.

The owner rejected the published 1.3.1 single-window preview: duplicate chrome, empty hero, oversized editor and competing first-run actions are confirmed anti-references. Earlier visual approval is reopened. This contract records the replacement implemented at source `b069a49`; it claims neither visual acceptance nor production readiness. The [native product pipeline](docs/design/native-product-pipeline.md) and existing Factory tracker own research, independent critique, implementation, confirmation and delivery.

The owner's Refero Apple, Linear, Cursor, Vercel, Intercom, Superhuman and Dala references guide quiet surfaces, alignment and restrained action hierarchy. Refero measurements and reconstructed HTML are interpretations, not source components or native specifications. Uploaded desktop-product references inform compact navigation and adjacent muted context. Uiarc is inspiration, not a dependency or a claim every demo was viewed. No marketing heroes, imported fonts, CSS layouts or theatrical motion.

**Key Characteristics:**

- One native workspace with one AppKit-owned toolbar.
- A stable bottom composer with local draft ownership.
- Warm light and charcoal dark surfaces with functional accent.
- Secondary routes adapt to remaining conversation space.
- Explicit connection, voice and sharing states with immediate stop controls.

## Colors

The frontmatter records the actual sRGB pairs from `Theme` in [Design.swift](Sources/Lilt/Design.swift). The light/dark suffixes identify appearance alternatives, not a tonal ramp. `Theme.adaptive` resolves Aqua or Dark Aqua at runtime; system/light/dark preference remains available. The native implementation remains runtime authority.

### Primary

**Theme accent** marks links, optional tool selection, focus strokes and the editor caret. This is the custom adaptive accent pair, not a promise to follow the user's macOS accent preference. Send, Stop and the primary Continue/Retry connection controls use **action/on-action**. Native AppKit/SwiftUI controls retain platform appearance and system selection behavior.

### Neutral

**Background** is the reading canvas; **rail** separates history; **fill** supports user messages and quiet controls; **fill-raised** supports composer/search/details; **fill-pressed** identifies selection. **Ink**, **muted** and **line** distinguish content, metadata and restrained dividers. **Warning** accompanies actionable text or symbols.

**The Source Pair Rule.** Preserve the actual adaptive Theme pairs and native semantic control colors. Do not invent intermediate ramps or treat a light-only swatch as the runtime color.

Verify readability, caret, focus and selection in light, dark and increased contrast. These are requirements, not a claim that a numeric contrast audit or assistive-technology pass has occurred.

## Typography

Use system typography through `Font.system` and `NSFont.systemFont`, SF Symbols through native APIs, and native control metrics. There is no bundled display font, CSS fallback stack or substituted font family.

Frontmatter lists reused roles. Message prose adds 6 pt line spacing; code uses system monospaced type. Brief empty-state text uses a local 20 pt regular style rather than a global display tier. Native toolbar labels and controls may use platform metrics rather than a forced shared text token.

**The Readable Density Rule.** Remove unnecessary space before shrinking type. Titles truncate or wrap deliberately and retain full accessible values or help text; tiny text is not density.

## Layout

All dimensions below are logical AppKit points and source choices, not Apple requirements. [NativeWorkspaceWindow.swift](Sources/Lilt/NativeWorkspaceWindow.swift), [WorkspaceView.swift](Sources/Lilt/WorkspaceView.swift) and [CoachViews.swift](Sources/Lilt/CoachViews.swift) own this geometry.

| Element | Implemented rule |
| --- | --- |
| Initial content | 1040 × 740 pt; native frame autosave when enabled |
| Minimum window | NSWindow.minSize 740 × 560 pt; a frame constraint, not guaranteed content size |
| History | 200 pt when visible and content width is at least 860 pt; otherwise history replaces chat on request |
| Details | 320 pt inline only if at least 560 pt of chat remains after visible history and 1 pt dividers; otherwise details replace chat |
| Combined inline thresholds | At least 1082 pt content with history; at least 881 pt without history, derived from the remaining-space rule |
| Transcript/composer measure | Maximum 680 pt before outer gutters, 24 pt horizontal gutters; naturally narrower with available space |
| Transcript spacing | 24 pt between messages, 24 pt top and 20 pt bottom insets |
| Composer editor | Measured NSTextView content height clamped to 28–140 pt, then native vertical scrolling; excludes shell padding/tool rows |

One real NSWindow owns standard traffic lights, title, drag, resize and full-screen behavior. A compact unified NSToolbar supplies history, new chat, mode, details and actions; AppKit owns overflow/menu tracking. Content adds no second toolbar or blank titlebar spacer. The title identifies the task or covered route, with an accessible Vale-qualified title.

The composer remains mounted across empty/populated, history, settings and details routes. When covered it is hidden from hit testing/accessibility and relinquishes its own first responder after committing marked text. Focus restoration checks live layout, draft identity, visible window and modal/sheet state. Its border reflects actual editor focus only while chat is visible. Back returns to the originating task. Test combined panels, not isolated thresholds.

**The Remaining Space Rule.** A prose maximum is not a chat minimum. Decide whether details sit alongside chat from usable remaining width, including visible panels and dividers.

## Elevation & Depth

The workspace uses flat adaptive surfaces and restrained borders, with no custom drop-shadow token. Native windows, menus, sheets and controls retain system depth. Do not wrap every action in a card or stack decorative borders.

ActionFeedback changes surface opacity without moving layout: feedback-color overlays are 6% on hover and 12% when pressed, absent when disabled; disabled opacity is 45%. Focus uses Theme accent; native controls retain platform feedback. These are implementation values, not universal accessibility standards.

No idle animation or launch choreography. Preserve Reduce Motion and Reduce Transparency: future optional motion must respect reduced motion, and translucency needs a solid legible alternative. Current custom surfaces are opaque; that alone is not runtime accessibility verification.

## Shapes

Search uses the search radius; quiet fields/buttons use the control radius; composer and selected message/guide containers use the composer radius, as listed in frontmatter. Native window/control shapes stay platform-owned. Reusable outlined feedback uses 0.7 pt strokes, focused feedback 1 pt, and composer/search 1 pt. Feedback must not change geometry.

## Components

### Native toolbar and history

Real NSToolbarItem/NSMenuToolbarItem controls carry labels, help, native symbols and validated menu routes. Settings remains a quiet persistent destination. Search covers messages, notes and files. Compact history rows use meaningful text/excerpts and an unsent-draft mark. Omit only the pristine active empty chat as a redundant retrieval row; preserve genuine drafts/files.

Active response, voice or selected-window context exposes a high-priority Stop toolbar item. A compact activity label remains when secondary routes cover chat, identifying starting/listening/speaking/conversation, thinking and shared/live/refreshing-window states. Full text remains in help and native overflow representation.

### Composer and connection

The plain NSTextView preserves native typing, IME, selection, undo and clipboard/file handling. Return sends only when permitted; Shift–Return inserts a line and marked text is protected. Clear undo at draft ownership changes. Async completions validate session/request identity; browser return never sends automatically.

| State | Composer behavior |
| --- | --- |
| Disconnected | Local drafts/files work; one Continue with ChatGPT action replaces unavailable Send, with adjacent explanation |
| Connecting | Finish-in-browser explanation, local progress and Cancel; retain draft/files |
| Validation/error | Precise error and Retry connection when applicable; preserve local work |
| Connected empty | Short invitation by the focused editor and normal Send; no setup hero |
| Connected restored | Resume work directly; the compact plan-usage/status row remains current implementation |
| Busy | Stop replaces Send, thinking is visible and continued drafting remains available |
| Failed/retry | Preserve message/files/request ownership and offer Retry message when valid |
| Paused | Explain mic/sharing are off and offer Resume; preserve draft |

File imports show compact accessible Adding files… feedback beside the composer and in Files; covered routes keep passive toolbar status. When another chat owns the import, that status names the owner. Typing remains available; Stop response does not cancel file imports. Failed-question Retry remains visible after navigation or relaunch and preserves newer drafts/files.

Files, selected-window context, Web and Voice remain subordinate tools. Web on/off is saved per chat, visible and accessibility-labeled. Opt-in does not establish hosted-tool success; account/workspace/model availability applies. No permanent Ready-to-type or idle voice footer.

### Context, voice and retained routes

Selection explicitly names one window. Live refresh is local with one bounded RAM preview; screen context refreshes at request time and sends only on a question/guide action. Preview, Change and Stop sharing remain available. No startup capture or automatic window choice.

Voice groups Talk, Conversation and read-aloud. Starting/listening/speaking/conversation states use words/symbols and immediate Stop. Conversation rearms only after explicit opt-in and completed playback. Pause, Escape, sleep/lock, session changes and errors stop it. Do not call this full-duplex or network streaming. Declining screen/microphone permission leaves typing available.

Preserve Learn/hints/pointing/walkthrough/guide, timer, notes/files, rename/export/Forget and read-aloud routes. A guide that sends/clears an existing draft keeps its confirmation. Notes/previews stay in the workspace. Native file/save/permission/updater dialogs and temporary click-through pointing feedback retain their limited roles. Back restores the originating task.

### Data, accessibility and consent

Preserve legacy local.lilt.companion/storage identifiers, chats, drafts, settings, attachments and assistant persona. Store sessions atomically. Uploaded files remain with chats; captured screenshots and microphone audio are not retained. Forget purges target content from the legacy backup and reports failures with retryable state. Never log credentials, microphone audio or user screenshots. Only explicitly enabled supported web search may reach the model; no command/file/app/browser/code tools, paid fallback or launch-on-login registration.

Controls require readable labels, accurate selected/disabled/pressed states and visible focus without layout movement. Preserve keyboard/IME/undo and system accessibility settings. Inspect light/dark/increased contrast, keyboard routing, modal focus, native caret/selection, Reduce Motion and Reduce Transparency separately from static rasters.

### Evidence and acceptance

Follow [research → independent critique → native implementation → complete-window confirmation and fresh review](docs/design/native-product-pipeline.md). The current live compiler is Swift 6.2.4; Swift 6.1.2 notes are historical. Minimum macOS remains 14; check APIs against the actual SDK. Impeccable's launcher already ran and has no macOS enum/reference: do not rerun it or relabel Vale as web/iOS.

Inspect minimum/default/wide, light/dark, realistic history/long titles, disconnected/error, conversation/retry/Learn, files/notes/settings and active context/voice combinations. First-pass images in artifacts/native-ui-1.3.2-first are generated in-process native evidence only. Their known sourceRevision value 54b0fd1a is a sidecar typo and must not establish revision provenance or final confirmation. Final native confirmation and formal reviews remain pending at this documentation pass.

Full-frame in-process raster can expose chrome defects but does not prove compositor output, physical input, assistive-technology behavior, real microphone/screen consent, genuine provider use, hosted search, official third-party ChatGPT authorization, package/feed publication or target-laptop installation. Keep acceptance classes distinct. Missing input/account capability keeps its gate open while independent work proceeds. Never overwrite a published version; preserve updater trust/key custody and the prior stable feed until stable gates pass. Publication is authorized for this task, but this document supplies no release acceptance. Remove old installed copies only after replacement launch verification while preserving user data.

## Do's and Don'ts

### Do

- **Do** keep one native toolbar and make the answer and composer primary.
- **Do** preserve the mounted editor, draft identity and visible focus across secondary routes.
- **Do** evaluate combined history/details width from remaining chat space.
- **Do** retain every capability and explicit consent boundary while simplifying hierarchy.
- **Do** report implementation, native visual inspection, physical input, provider, package/feed and installed outcomes separately.

### Don't

- **Don't** restore duplicate chrome, empty hero, oversized editor or competing connection/send actions.
- **Don't** substitute web components, imported fonts, iOS dimensions or fabricated tonal ramps for native source truth.
- **Don't** hide active voice/sharing without visible state and an immediate Stop route.
- **Don't** infer hosted-tool success, real consent or third-party support from fixtures or familiar login branding.
- **Don't** call the redesign accepted or production-ready from compilation, assertion counts, worker completion or first-pass rasters.
