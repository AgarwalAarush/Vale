# Lilt
Native macOS learning companion. Preserve the original dark floating capsule and coach visual system. Typing is a first-class feature, voice optional. Avoid full-height chat sidebars and generic dashboards.

Build: `scripts/build.sh`. Core tests: `swift run --disable-sandbox LiltCoreChecks`. Native UI checks: `scripts/verify.sh` (added with app harness). Render and inspect screenshots of the actual AppKit/SwiftUI views, not a browser reconstruction.

Never log credentials, microphone audio, or screenshots. No automatic window sharing, microphone activation, paid fallback, production publishing, or launch-on-login registration. Store sessions atomically and preserve drafts. Every async completion must validate its session and request identity. Screen context must be refreshed at request time. No model tool access is needed for tutoring.
