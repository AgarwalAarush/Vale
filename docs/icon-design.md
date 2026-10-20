# Vale icon

The app icon uses a single matte graphite tile and a sculpted, folded ribbon V in cool porcelain and muted periwinkle. The broad silhouette keeps it readable in the Dock and the small in-app badge. Avoid nested tiles, typeset initials, tiny details and decorative AI symbols. Preserve the app's existing dark floating visual system.

The canonical artwork is `Resources/Vale.png`, a 1024 × 1024 PNG with alpha outside the tile. `scripts/icon.swift` resamples this master into the ten standard macOS iconset entries; `scripts/build.sh` packages the resulting ICNS and the same PNG for the native badge. Do not redraw or replace the artwork during builds. Legacy identifiers remain unchanged.

Artwork generated on 2026-10-17 with the built-in image generation tool. The generated image was resized to the 1024-pixel master without changing its artwork or alpha.

## Local verification

On 2026-10-17, the native x86_64 build and ad-hoc signature verification passed. The bundled PNG and ICNS match the source assets byte for byte. All ten iconset PNGs have the expected pixel dimensions and alpha; the ICNS round-trip preserves those sizes. The master and actual 16, 32, 64 and 128 pixel files passed visual review.

Finder/IconServices resolves the rebuilt app's new icon: `NSWorkspace.shared.icon(forFile:)` was rendered at 128 pixels and visually inspected, showing the folded V with transparent corners.

The isolated native harness passed 61/61 fixture checks. The real native chat and library view snapshots show the new badge, with results in `artifacts/icon-native-20261017/` and the log at `artifacts/icon-native-20261017.log`. These checks do not add hardware, provider, Apple Silicon or public-release acceptance. The rebuilt local app is `dist/Vale.app`.

## Generation prompt

```text
Use case: logo-brand
Asset type: finished native macOS app icon for Vale, a quiet floating AI companion for writing, coding, and conversation.
Primary request: Create one exceptionally polished, distinctive app icon. A single dark graphite rounded-square tile carries an abstract sculptural V formed by one continuous folded satin ribbon. This should look like a carefully art-directed shipping Mac app icon, beautifully restrained, tactile and immediately readable in the Dock.
Subject: One bold open V / valley silhouette, two broad tapering ribbon arms with one elegant folded bend at the bottom, generous dark negative space. Slightly asymmetric fold gives it its own identity; from a distance the silhouette is a clear V. The ribbon is cool porcelain and pale periwinkle on its lit faces, with restrained violet on the inner fold, and softly lit satin-silver edges. Broad simple surfaces, no thin details. The V fills about 62% of the tile width and 60% of its height and is optically centered.
Scene/backdrop: The icon itself is ONE dark charcoal macOS rounded-square tile with a superellipse-like silhouette, a barely visible bevel and delicate top-edge highlight. The tile occupies 82% of the square canvas, centered, with fully transparent space outside the tile. The face is matte graphite, almost black. Subtle depth and soft ambient occlusion ground the ribbon on the tile.
Style/medium: Premium restrained 3D product icon, precise geometric silhouette, soft studio lighting from upper left, clean refined material work, beautiful at 1024 pixels and legible at 32 pixels. Near-frontal orthographic view. Not a presentation mockup.
Color palette: graphite / off-white / muted periwinkle, a small amount of deep violet in the fold; no multicolor rainbow.
Composition/framing: Square 1024x1024 image, exactly one finished icon centered, crisp silhouette and corners, transparent outside.
Constraints: No letters typeset in a font, no words, no caption, no sparkle, no stars, no chat bubble, no robot, no microphone, no nested rounded squares, no scenery, no additional small objects, no noisy textures, no heavy bloom, no cyberpunk neon, no stock generic AI knot, no watermark. The abstract ribbon itself makes the V. Genuine alpha transparency outside the single tile.
```
