#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
LILT_APP="$PWD/dist/Vale.app"
LILT_CACHE="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$LILT_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$LILT_CACHE"
mkdir -p "$LILT_APP/Contents/MacOS" "$LILT_APP/Contents/Resources" "$LILT_APP/Contents/Frameworks" "$LILT_CACHE"
swift -module-cache-path "$LILT_CACHE" scripts/icon.swift "$PWD/Resources"
iconutil -c icns Resources/Vale.iconset -o Resources/Vale.icns
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$LILT_CACHE"
LILT_NATIVE_ARCH="$(uname -m)"
case "${VALE_ARCH:-native}" in
  universal) LILT_OTHER_ARCH="$([[ "$LILT_NATIVE_ARCH" == arm64 ]] && print x86_64 || print arm64)" ;;
  arm64|x86_64) LILT_OTHER_ARCH="${VALE_ARCH}" ;;
  native) LILT_OTHER_ARCH="$LILT_NATIVE_ARCH" ;;
  *) print -u2 "Choose VALE_ARCH=native, arm64, x86_64, or universal."; exit 1 ;;
esac
if [[ "$LILT_OTHER_ARCH" != "$LILT_NATIVE_ARCH" ]]; then
  swift build -c release --triple "$LILT_OTHER_ARCH-apple-macosx14.0" --scratch-path ".build-$LILT_OTHER_ARCH" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache-$LILT_OTHER_ARCH"
fi
if [[ "${VALE_ARCH:-native}" == universal ]]; then
  lipo -create .build/release/Lilt ".build-$LILT_OTHER_ARCH/$LILT_OTHER_ARCH-apple-macosx/release/Lilt" -output "$LILT_APP/Contents/MacOS/Lilt"
elif [[ "$LILT_OTHER_ARCH" != "$LILT_NATIVE_ARCH" ]]; then
  cp ".build-$LILT_OTHER_ARCH/$LILT_OTHER_ARCH-apple-macosx/release/Lilt" "$LILT_APP/Contents/MacOS/Lilt"
else
  cp .build/release/Lilt "$LILT_APP/Contents/MacOS/Lilt"
fi
cp Resources/Info.plist "$LILT_APP/Contents/Info.plist"
cp Resources/tutor.md Resources/reply.schema.json Resources/Vale.png Resources/Vale.icns "$LILT_APP/Contents/Resources/"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$LILT_APP/Contents/Frameworks/Sparkle.framework"
cp -f .build/checkouts/Sparkle/LICENSE "$LILT_APP/Contents/Resources/Sparkle-LICENSE.txt"
python3 scripts/configure-updates.py "$LILT_APP/Contents/Info.plist"
codesign --force --sign - --identifier local.lilt.companion "$LILT_APP"
codesign --verify --deep --strict "$LILT_APP"
lipo -archs "$LILT_APP/Contents/MacOS/Lilt"
print "Built $LILT_APP"
