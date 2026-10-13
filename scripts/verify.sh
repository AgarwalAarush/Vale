#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
MYTHOS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
MYTHOS_SERIES="$MYTHOS_VERSION"
MYTHOS_INTEGRATION=false
MYTHOS_REPEAT=false
for option in "$@"; do
  case "$option" in
    --integration) MYTHOS_INTEGRATION=true ;;
    --repeat) MYTHOS_REPEAT=true ;;
    *) print -u2 "Usage: scripts/verify.sh [--integration] [--repeat]"; exit 1 ;;
  esac
done
mkdir -p artifacts
python3 scripts/check-update-config.py
swift run --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH" LiltCoreChecks --results "$PWD/artifacts/core-results-$MYTHOS_SERIES.json" > "artifacts/unit-tests-$MYTHOS_SERIES.log" 2>&1
scripts/build.sh > "artifacts/universal-build-$MYTHOS_SERIES.log" 2>&1
python3 scripts/run-bounded.py 150 dist/Mythos.app/Contents/MacOS/Lilt --self-test "$PWD/artifacts/native-ui-$MYTHOS_SERIES-final" > "artifacts/native-ui-$MYTHOS_SERIES-final.log" 2>&1
if $MYTHOS_REPEAT; then
  python3 scripts/run-bounded.py 150 dist/Mythos.app/Contents/MacOS/Lilt --self-test "$PWD/artifacts/native-ui-$MYTHOS_SERIES-final" > "artifacts/native-ui-$MYTHOS_SERIES-repeat.log" 2>&1
fi
if $MYTHOS_INTEGRATION; then
  python3 scripts/run-bounded.py 540 dist/Mythos.app/Contents/MacOS/Lilt --integration-test "$PWD/artifacts/integration-$MYTHOS_SERIES-final" > "artifacts/integration-$MYTHOS_SERIES-final.log" 2>&1
fi
print "Verification passed. Native screenshots and results are in artifacts/."
