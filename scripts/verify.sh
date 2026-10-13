#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p artifacts
python3 scripts/check-update-config.py
swift run --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH" LiltCoreChecks > artifacts/unit-tests.log 2>&1
scripts/build.sh > artifacts/release-build.log 2>&1
python3 scripts/run-bounded.py 90 dist/Mythos.app/Contents/MacOS/Lilt --self-test "$PWD/artifacts/native-ui"
if [[ "${1:-}" == "--integration" ]]; then
  python3 scripts/run-bounded.py 360 dist/Mythos.app/Contents/MacOS/Lilt --integration-test "$PWD/artifacts/integration"
fi
print "Verification passed. Native screenshots and results are in artifacts/."
