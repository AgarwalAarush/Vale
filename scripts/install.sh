#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
LILT_INSTALL_DIR="${LILT_INSTALL_DIR:-$HOME/Applications}"
LILT_INSTALL_TARGET="$LILT_INSTALL_DIR/Mythos.app"
if [[ -e "$LILT_INSTALL_TARGET" ]]; then
  print -u2 "Mythos already exists at $LILT_INSTALL_TARGET. This installer will not replace it."
  exit 1
fi
codesign --verify --deep --strict dist/Mythos.app
mkdir -p "$LILT_INSTALL_DIR"
ditto dist/Mythos.app "$LILT_INSTALL_TARGET"
codesign --verify --deep --strict "$LILT_INSTALL_TARGET"
open "$LILT_INSTALL_TARGET"
print "Installed $LILT_INSTALL_TARGET"
