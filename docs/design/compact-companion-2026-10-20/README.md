# Vale compact companion — 2026-10-20

Status: **Pearl Glass approved by the owner on 2026-10-20**: “this one is phenomenal lets build this out”. The selected comp is 01-pearl-glass.png; the prior Lens recommendation was not selected.
Native implementation is now in progress. Prior exploration images remain design references, not runtime evidence.

## Product correction

The owner's latest description replaces the large-window direction. Vale is a
keyboard-shortcut summoned companion beside the user's work, positioned at the
top right. Its resting footprint is approximately **300 × 45 logical points**.
One continuous floating panel expands in place for a typed or spoken question,
selected context and an answer, then can collapse again. The textbook or other
working app remains dominant. A full workspace with permanent history/sidebar is
a rejected direction, even if its code and generated native checks pass.

Typing and dictation are equally accessible. Keep explicit window context,
screenshots and files. Preserve existing chats, Learn, notes, timer, read-aloud,
history/retrieval, settings and direct ChatGPT connection; expose secondary routes
on demand without turning the initial surface into a full workspace. Preserve
legacy identifiers, storage and data ownership. One assistant panel means no
separate capsule plus detached conversation window.

## Proposed geometry and interaction

These are proposed implementation defaults, not measurements certified by an
image model, Apple requirements, or already implemented behavior.

- Rest: 300 × 45 pt. Editor placeholder and microphone are immediately available.
- Question: roughly 320–340 × 120–185 pt, growing with draft/context.
- Short answer: roughly 320–350 × 240–320 pt. Long replies scroll inside a
  bounded expansion rather than extending offscreen.
- Keep the top-right anchor fixed; grow left/down within the active screen's
  visible safe frame, initially inset 18–24 pt. Respect menu bar and screen edges.
- Use existing Control–Option–Space registration unless deliberately changed.
  Summon never activates the microphone or chooses a window automatically.
- Retain the same native text editor across states. Preserve draft, selection,
  IME and undo. Return/Shift–Return retain their established behavior.
- Explicit microphone click starts dictation. Listening has transcript, waveform
  and immediate Stop. No idle waveform. Screen-context chip names the selected
  source and offers removal; selected context and sent context remain distinct.
- Escape stops active capture/voice first according to a documented priority,
  then collapses/dismisses safely and returns focus to the prior app. Never lose
  a draft, pending attachment or failed-message retry.
- Keep visible tool targets near 28 pt even when the glyph is smaller.
- Reserve a proposed interruptible 140–180 ms transition for shape changes;
  reduced motion uses an immediate state change.

## Material and typography

The owner explicitly requests a Liquid Glass look. Use an actual native
material where supported, with a legible frosted/solid alternative on older
systems and when Reduce Transparency is enabled. Verify against the real SDK
before choosing an API. Do not promise identical optical effects on macOS 14.

SF system type, approximately 13 pt input and 13–14 pt reply text with 19 pt
leading, 12–14 pt insets, thin optical edges and a restrained shadow. Keep the
reading area stable over light pages, dark content and busy imagery. The tiny
shell and controls can have glass depth; avoid nested translucent cards around
every answer or action. The existing folded V is retained in implementation;
generated V glyphs are placeholders in these concepts.

Apple's material guidance separates the floating functional layer from content
and emphasizes legibility. [Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/),
[custom SwiftUI glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

## Concepts and source roles

| Concept | Structural idea | Finding |
| --- | --- | --- |
| [Pearl glass](01-pearl-glass.png) | Input pill unfolds into a short conversation | Strong quiet default; generated answer grew beyond requested copy and needs a tighter real layout. |
| [Smoke glass](02-smoke-glass.png) | Voice-led ribbon, listening transcript, compact reply | Useful dark/listening direction; generated extra paragraph and serif reply text are not implementation instructions. |
| [Reading lens](03-reading-lens.png) | Screenshot/context annotation with explanation and follow-up | Recommended compact source structure; corrected to an on-screen PDF rather than the first generation's physical book. |

Each board shows chronological states of one concept; **the three panels are
not simultaneous assistant windows**. Generated images do not certify exact
point sizes, authentic macOS chrome, native glass behavior, accessibility or
correctness of background textbook prose. The final lens correction shortens
the answer and uses an accurate example. Discarded physical-book generation is
not a final project deliverable.

User references: Refero/Linear contribute restraint and hierarchy; Uiarc
contributes the idea of a trigger growing into its task. EstateOps reference
stills contribute precise density and surface discipline, not dashboard layout.
Freya contributes compact controls and independent reading typography; Stratum
contributes precise alignment, metadata hierarchy and thin rules. No personal
books, databases, chats, screenshots or credentials were uploaded to generation.

## Review and acceptance

Root generated three concepts with the built-in image tool and one targeted
lens correction. A separate read-only design agent inspected Freya/Stratum
design sources and the generated final candidates. See review.md for its
actual findings; a review recommendation is not owner approval.

Current finish line is the approved Pearl companion implemented, natively inspected, independently reviewed and packaged. Figma is optional design tooling; its unresolved team choice does not block the approved native implementation. No Figma file is created in an unselected team.

Implement the approved Pearl compact native shell and validate real
1×/2× geometry, long questions/replies, math, attachment removal, dictation
interruptions, repeated shortcut summon, focus restoration, display/Space
placement, reduced transparency/motion and zero overlapping assistant panels.
Retest the retained capabilities and previously repaired draft/retry/import
ownership paths. Genuine service, hardware, package/feed and laptop acceptance
remain separate. Published 1.3.2 preview evidence applies to the old large UI and
does not establish acceptance of this compact redesign.

[prompts.json](prompts.json) preserves exact generation prompts and refinement.


## Approved direction contract

**Thesis:** one small helper beside the work, with a continuous Ready → Ask → Answer shell.

**World:** the approved Pearl comp owns geometry, visual hierarchy and material intent: light frosted pearl, dark ink, thin optical rim, quiet shadow, compact system type and a dark send button. Offer a coherent dark appearance while retaining this topology.

**Task:** summon with Control–Option–Space, type or explicitly dictate, optionally select context, send, read and follow up. History and retained tools reveal in the same panel on demand.

**Composition:** 300×45pt resting input with canonical V, Ask Vale…, mic and overflow. Expansion keeps its top-right anchor, reveals source chips/question/plus/mic/send, then the latest question and naturally rendered answer with copy/read-aloud above a compact follow-up field.

**Translation:** native text/controls and native material, never a rasterized mockup. The reference background, monitor bezel and generated prose/equation are context examples. Actual SDK/OS capabilities govern optical rendering; the macOS15 host cannot exercise macOS26 Liquid Glass; the matching installed XcodeSDK can compile its availability-guarded path.

**Finish:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
