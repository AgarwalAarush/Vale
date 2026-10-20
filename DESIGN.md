# Vale design

## Direction

A quiet native reading workspace: one resizable macOS window, where the conversation and composer carry the interface. The owner explicitly requests a substantial single-window redesign, confirmed capability preservation and code-first native inspection. This replaces the legacy capsule/coach/library composition while preserving Vale's name and ribbon-V artwork.

Design read: a personal native assistant for recurring chat, document and learning work, with an editorial, restrained language. Taste values: DESIGN_VARIANCE5, MOTION_INTENSITY2, VISUAL_DENSITY5; native Operate behavior takes precedence over marketing motifs.

## Reference interpretation

- [Intercom](https://styles.refero.design/style/12255b63-e506-4bc1-a4cd-d05487de32f3): warm light neutrals, careful spacing and hairlines. Translate into readable native density, not a website hero.
- [Superhuman](https://styles.refero.design/style/418b374a-be64-44f0-b17e-1d45308c7e62): disciplined action hierarchy and comfortable text. Exclude marketing photography.
- [Dala](https://styles.refero.design/style/e5f5f8cf-e68d-4ed1-bbf5-6b67569af648): clarity and negative space inform the dark counterpart. Exclude particles and theatrical display scale.

## First viewport and layout

Default1040×740, minimum740×560, verified at compact/default/wide sizes. One standard NSWindow, normal traffic lights, native resize/minimize/fullscreen and remembered frame. Collapsible history rail (~224points), compact toolbar, readable conversation (~680point max measure), bottom composer. Below~860points the rail yields to the current task. File/notes/context details live in an in-window inspector; at narrow widths a detail route replaces the reading region with a clear Back action. Settings is an in-window route, never a detached preferences app.

First launch: one brief invitation, actual editable composer, useful Attach/Share/Talk actions. No extra status capsule, giant empty slab, duplicated branding, decorative prompt cards or permanently visible configuration badges. Populated conversation prioritizes the answer; readable author distinctions and code/links/attachments remain literal.

## Tokens

Use dynamic semantic colors throughout native views and NSTextView/PDF controls. Default System appearance; explicit Light/Dark override may be offered.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | #f7f6f2 | #18191d |
| Navigation | #eeede8 | #141519 |
| Raised/input | #ffffff | #22242a |
| Primary text | #252629 | #f0f0ed |
| Secondary text | #67686b | #b0b1b8 |
| Divider | #ddddd6 | #363840 |
| Accent | #5759c6 | #b9bcff |
| Primary action | #28292d | #ecece8 |

Semantic warning/error colors must remain legible in both modes. Do not reuse white opacity as a light-surface fill. Contrast≥4.5:1 body/placeholder,≥3:1 large text and meaningful controls.

System SF typography: body15, controls13, secondary12, section20–24, welcome30–32 with normal/light weight. No all-caps decorative eyebrows, microscopic labels, custom marketing fonts or icon-font substitutes. SF Symbols for native controls, with accessible labels/help.

Shape scale:8point controls/rows,12point composer and real inset groups; native window shape. Depth comes from surface tone and one quiet divider, not glass borders plus shadows. Spacing4/8/12/16/24/32.

## Navigation and interaction

Selecting history resumes it directly in the same window. Commit active IME text and persist old draft/pending files before changing chat identity. Settings and inspector navigation preserve composer/selection/scroll state. New chat retains the previous draft in history. Rename/export/Forget remain discoverable and deliberate.

Share state and Stop sharing remain visible when active; mic/listening/playback/conversation state and stop controls stay inside the window. Native permission/file/save dialogs and intentional transient click-through pointing annotation are the only secondary OS surfaces; no second assistant content panel. Closing pauses transient capture/voice and preserves data. Reopening never grants consent or rearms capture.

The signature interaction is continuity: revealing context beside the answer and returning to the same composer without changing windows. Transitions are brief state feedback; Reduce Motion removes animation. Reduced Transparency gets solid surfaces. No idle pulse animation.

Quiet actions share an enabled hover/pressed surface and a keyboard focus outline, without moving content. Composer focus is observed from its mounted native text view; only the visible, actually focused editor receives an accent stroke. History search uses its existing native focus state for the same stroke, and literal excerpts keep matching text in view. Notes and Files are direct detail destinations; previews name their current content. An inline inspector closes with “Close details,” while a replacing route returns with “Back to chat.” Notes and Files use the existing 680-point content measure with aligned 24-point gutters, shrinking naturally in the 320-point inspector. Related read-aloud, consent text and voice options share one 12-point-spaced settings group.

## Delivery and verification

Inspect actual native empty/populated/history/settings/files/notes/context/loading/retry/guide states in light/dark at compact/default/wide sizes in one batched pass, then one confirmation pass after fixes. Screenshots must use generated fixtures, not private user content. Native interaction, genuine provider, signing/update installation, hardware and target-laptop evidence stay separate. A configured label without a real signed update path is not updater completion.
