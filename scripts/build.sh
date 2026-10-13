#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p dist/Lilt.app/Contents/MacOS dist/Lilt.app/Contents/Resources
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"
cp .build/release/Lilt dist/Lilt.app/Contents/MacOS/Lilt
cp Resources/Info.plist dist/Lilt.app/Contents/Info.plist
cp Resources/tutor.md Resources/reply.schema.json dist/Lilt.app/Contents/Resources/
if [[ -f Resources/Lilt.icns ]]; then cp Resources/Lilt.icns dist/Lilt.app/Contents/Resources/; fi
codesign --force --sign - --identifier local.lilt.companion dist/Lilt.app
codesign --verify --deep --strict dist/Lilt.app
print "Built ${PWD}/dist/Lilt.app"
