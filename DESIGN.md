# Vale design handoff

If a visual choice is missing, pick the quieter option, write it into this file, and keep building. Ask nothing.

The reference images are `docs/images/vale-capsule.png` and `docs/images/vale-chat.png`. Match their border treatment, type density, and spacing. Token values below are the sRGB reading of `Theme` in `Sources/Lilt/Design.swift`. Change that file and this document together.

## Product

Vale is a native macOS companion for writing, coding, documents, and talking through one selected window. The person using it opens a floating capsule, types, and optionally shares a window, dictates, or asks for a short step guide. General chat is the start. Learn mode is a choice. The assistant's name is Lilt. The app name is Vale. Bundle id `local.lilt.companion`, preference keys, and `Application Support/Lilt` stay as they are.

Primary loop: summon with Control–Option–Space, type, Return to send. Share a window only when the work is about that window. Live refresh is a separate opt-in and stays on device until a question or guide step. Pause or Escape stops voice and sharing.

## Locked decisions

| Choice | Decision |
| --- | --- |
| Mode | Dark only. `preferredColorScheme(.dark)` and `NSAppearance.darkAqua`. |
| Accent | `#91ABFF`. Caret, live and listening state, guide kicker, text buttons, send button. |
| Layout | Floating capsule, compact coach card, separate library window. |
| Type | SF Pro for UI. SF Mono for timers, IDs, and counts. |
| Density | Capsule `430×62`. Coach `410×480`, expanded `560×700`. Library `900×650`, minimum `760×540`. |
| Motion | Under 200ms. No decorative loops. |
| 3D | Off. |
| Light theme | Do not add one. |
| Web stack | Do not add one. |

## Color

| Token | Value | Use |
| --- | --- | --- |
| Background | `#1A1C1F` | Library window, coach glass tint at 86% over HUD material. |
| Ink | `#F0F2F5` | Primary text and icons. |
| Muted | `#9CA3AD` | Secondary copy, eyebrows, timestamps, optional labels. |
| Accent | `#91ABFF` | See locked decisions. Send button fill is accent at 35% when it can submit, 12% when idle. |
| Hairline | white at 14% | `0.7`pt stroke on glass and fields. |
| Quiet line | white at 9% | `Theme.line`. Dividers and quiet button borders. |
| Fill | white at 2.5–7.5% | Fields, context strip, pressed and selected rows. |
| Warning | system orange | Shortcut conflicts, provider and deletion errors. Pair with a recovery button in accent. |
| Mark | `#C2CFFF` to `#91ABFF`, label `#213B9E` | `LogoMark` only. |

Selected library rows use white at 6.5%. Guide cards use accent at 6% fill and 16% stroke. Do not introduce a second brand color, a green success wash, or a red destructive fill. Destructive actions stay in confirmation copy.

## Typography

- Capsule title: 12pt medium, one line.
- Timer: 13pt semibold, SF Mono, `monospacedDigit()`.
- Coach title: 15pt semibold.
- Empty headline: 24pt medium, tracking `-0.55`.
- Library title: 29pt medium, tracking `-0.8`.
- Body and composer: 13–14pt. Secondary lines 11–12pt muted.
- Eyebrows: 9pt medium, tracking about `1.1`, muted, short uppercase.
- Buttons: 12pt medium. Guide actions: 10pt.
- Line length inside the coach stays within the card. Do not set marketing measures like `65ch` on these panels.
- Prices, timers, step counts, file counts, and "Ns ago" use `monospacedDigit()`.

## Layout

Surfaces, in order of how someone meets them:

1. **Capsule.** Borderless floating panel, continuous 20pt corners, HUD glass, 20pt horizontal padding, height 62. Audio mark, title, microphone, Pause, overflow. Sits near the top-right of the visible screen.
2. **Coach.** Borderless floating panel. Header, context strip, optional guide card, transcript, composer. Compact `410×480` at the lower right. Expanded `560×700` on the corner control. Collapse returns to the capsule. This is not a sidebar.
3. **Library.** Titled window, transparent titlebar, `900×650`. A `194`pt rail lists chats. A 1pt quiet line separates it from search, empty state, session detail, or settings. The rail is history navigation, not the conversation UI.
4. **Previews.** File preview `800×550`. Shared-window preview `800×520`. Both use the same background.
5. **Point.** A highlight frame on the selected window. Missing geometry explains itself and draws nothing.

Corners already in use: capsule and coach glass 20, buttons and fields 8–10, logo mark at 25% of its size, icon buttons as circles. Keep new controls inside that set.

## Spacing

Base unit is 4pt. Use 4, 8, 12, 16, 20, and 24. The capsule and coach already inset at 15 and 18pt. Leave those insets. Do not renormalize them.

- Capsule: horizontal 20, height 62, control gaps 12–15.
- Coach header: horizontal 18, top 15, bottom 11. Transcript stack spacing 20.
- Context strip and guide card: inset 12, outer horizontal 18.
- Library home: horizontal 42, top 56, bottom 40. Rail width 194.

## Motion

- Icon hover and button press are immediate opacity changes.
- Coach compact and expand may animate the window frame, as `AppController` does now.
- New micro-interactions stay under 200ms. A SwiftUI spring, when one is required, uses a short response and high damping. No bounce.
- The audio mark is five static bars. Listening changes color to accent. It does not animate on a loop.
- Do not add marquees, blur reveals, number tickers, border beams, or shader canvases.

## Components

Build controls from the existing primitives.

| Need | Use |
| --- | --- |
| Panel surface | `GlassSurface` for capsule and coach. Flat `Theme.background` for library and previews. |
| Text button | `QuietButton`. `filled: true` for the one primary in a row, such as Pause or New chat. |
| Icon button | `IconButton` with an SF Symbol, 13pt medium, 30×30 hit area, accessibility label, and help text. |
| Composer | `DraftEditor`. Return sends. Shift–Return inserts a newline. Escape cancels. Paste may attach files or an image. |
| Mode and overflow | Native `Menu`, borderless, indicator hidden. |
| Search | Plain `TextField` inside the existing hairline field. |
| Confirm forget or rename | `confirmationDialog` and `alert`. |
| Voice disclosure | Existing `VoiceSettings` group. |

SF Symbols at the sizes already used (10–16pt). Do not import a second icon set.

## Screens

Each screen ships empty, loading, error, populated, and keyboard-reachable states.

1. **Capsule, idle.** Title "Vale". Mic idle. Pause enabled once a chat exists.
2. **Capsule, live.** Window glyph in accent. Help text says live context is on.
3. **Coach, empty, Ask.** Eyebrow, "How can I help?", one line of support, context strip on "Share a window" / Optional, composer placeholder.
4. **Coach, empty, Learn.** "What are we working through?" and the hint line.
5. **Coach, provider missing.** The Codex install line plus a Settings action. The draft remains.
6. **Coach, guide.** Step kicker, current step, Back, Point it out, Next step. Busy and paused disable the row.
7. **Coach, limited context.** The recent-messages notice and a History action.
8. **Library, no chats.** "Your chats", search field, "A place to pick up the thread."
9. **Library, search miss.** "No chats found." and the retry line.
10. **Library, list and detail.** Title, last line or attachment count, date, rename, export, Forget.
11. **Settings.** Provider, voice, and the existing recovery path from an error.
12. **Failure.** Orange message, draft kept, Settings or Retry when that action exists.

## Sample chats

Use these when a view needs realistic rows. They are fixtures, not a person's history.

| Title | Mode | Detail | Last line |
| --- | --- | --- | --- |
| Release notes for 1.2 | Ask | Updated today | Sparkle stays manual until a signed feed exists. |
| Where the timeout is thrown | Learn | Step 2 of 4 | WindowContext waits at most six seconds, then keeps the draft. |
| Two fixture pages | Ask | 2 files | harbor-note.pdf and harbor-scan.pdf are attached. |
| New chat | Ask | Empty | Ready when you are. |

Search against "timeout" returns the Learn row. Search against "harbor" returns the file row. An empty query shows all four, with New chat using the empty-state sentence when it has no messages.

## Keyboard

- Control–Option–Space summons the composer.
- Return sends. Shift–Return inserts a newline.
- Escape pauses voice, sharing, and pending replies.
- Command–N starts a chat.
- The corner control expands and compacts the coach.
- A shortcut conflict is shown. It is not cleared silently.

## States

- **Loading.** "Refreshing…" on the context strip. Send becomes stop while a reply is in flight. Buttons that must not double-fire are disabled.
- **Empty.** The coach headlines and the library empty copy above. No skeleton dashboard and no fake metrics.
- **Error.** One orange line and a way forward: Settings, Retry Forget, or Refresh. Drafts and unrelated chats stay.
- **Populated.** Messages, guide card, attachment chips with remove, history rows.
- **Focus.** Composer insertion point is accent. Icon buttons expose hover. Every control has an accessibility label. Pointer hover is not the only way to reach an action.

## Do not add

Full-height chat sidebars, generic dashboards, light mode, a second accent, page gradients, neon glow, emoji feature cards, three-column feature grids, stock photos, looping motion, 3D scenes, web-component libraries, or a redesign that replaces the capsule with a centered marketing page.
