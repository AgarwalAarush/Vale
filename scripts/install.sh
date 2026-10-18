#!/bin/zsh
set -euo pipefail
umask 077

vale_replace=false
vale_dry_run=false
for vale_option in "$@"; do
  case "$vale_option" in
    --replace) vale_replace=true ;;
    --dry-run) vale_dry_run=true ;;
    --help|-h)
      print "Usage: install.sh [--replace] [--dry-run]"
      print "Installs VALE_APP_SOURCE (default: the repository's dist/Vale.app) into ~/Applications/Vale.app."
      print -- "--replace gracefully quits Vale/Lilt copies and trashes obsolete matching app bundles after a verified launch."
      print "Chat libraries, settings, credentials and macOS security permissions are never changed."
      exit 0 ;;
    *) print -u2 "Unknown option: $vale_option"; exit 2 ;;
  esac
done

vale_log() { print -r -- "[Vale] $*"; }
vale_fail() { print -ru2 -- "[Vale] $*"; exit 1; }
vale_plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
vale_identifier="local.lilt.companion"
vale_install_dir="$HOME/Applications"
vale_target="$vale_install_dir/Vale.app"
vale_source="${VALE_APP_SOURCE:-${0:A:h:h}/dist/Vale.app}"
[[ -d "$vale_source" ]] || vale_fail "App source is missing: $vale_source"
vale_source="$(cd "$vale_source" && pwd -P)"
vale_native_arch="$(/usr/bin/uname -m)"
if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then vale_native_arch=arm64; fi
vale_macos="$(/usr/bin/sw_vers -productVersion)"
autoload -Uz is-at-least

vale_architectures() {
  /usr/bin/osascript -l JavaScript - "$1" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
    var architectures = $.NSBundle.bundleWithPath(argv[0]).executableArchitectures;
    if (!architectures || !architectures.count) throw new Error('No executable architectures were found.');
    var labels = [];
    for (var index = 0; index < architectures.count; index++) {
        var type = ObjC.unwrap(architectures.objectAtIndex(index));
        var label = type === 16777223 ? 'x86_64' : type === 16777228 ? 'arm64' : type === 7 ? 'i386' : type === 12 ? 'arm' : 'CPU-' + type;
        if (labels.indexOf(label) < 0) labels.push(label);
    }
    return labels.join(' ');
}
JXA
}

vale_validate() {
  local vale_bundle="$1" vale_exec vale_version vale_build vale_minimum vale_arches
  [[ -d "$vale_bundle" && ! -L "$vale_bundle" ]] || vale_fail "Expected a real app bundle: $vale_bundle"
  [[ "$(vale_plist "$vale_bundle" CFBundleIdentifier 2>/dev/null)" == "$vale_identifier" ]] || vale_fail "Refusing a bundle with another identifier: $vale_bundle"
  [[ "$(vale_plist "$vale_bundle" CFBundlePackageType 2>/dev/null)" == APPL ]] || vale_fail "This is not a macOS application: $vale_bundle"
  vale_exec="$(vale_plist "$vale_bundle" CFBundleExecutable)"
  [[ -n "$vale_exec" && "$vale_exec" != */* && "$vale_exec" != . && "$vale_exec" != .. ]] || vale_fail "Invalid app executable name."
  [[ -x "$vale_bundle/Contents/MacOS/$vale_exec" ]] || vale_fail "App executable is missing: $vale_bundle"
  vale_version="$(vale_plist "$vale_bundle" CFBundleShortVersionString)"
  vale_build="$(vale_plist "$vale_bundle" CFBundleVersion)"
  [[ "$vale_version" =~ '^[0-9]+([.][0-9]+)*$' && "$vale_build" =~ '^[0-9]+([.][0-9]+)*$' ]] || vale_fail "Invalid app version or build number."
  vale_minimum="$(vale_plist "$vale_bundle" LSMinimumSystemVersion)"
  is-at-least "$vale_minimum" "$vale_macos" || vale_fail "Vale requires macOS $vale_minimum; this Mac runs $vale_macos."
  vale_arches="$(vale_architectures "$vale_bundle" 2>/dev/null)" || vale_fail "App executable is not a valid Mach-O file: $vale_bundle"
  [[ " $vale_arches " == *" $vale_native_arch "* ]] || vale_fail "This app does not contain this Mac's $vale_native_arch executable."
  /usr/bin/codesign --verify --deep --strict "$vale_bundle" || vale_fail "App signature verification failed: $vale_bundle"
  vale_log "Verified $vale_version (build $vale_build), $vale_arches: $vale_bundle"
}

# NSWorkspace identifies renamed/running copies by their actual bundle identifier.
# No UI scripting, forced termination, permission changes or credential access.
vale_app_action() {
  /usr/bin/osascript -l JavaScript - "$1" "$vale_target" <<'JXA'
ObjC.import('AppKit');
ObjC.import('Foundation');
function run(argv) {
    var identifier = 'local.lilt.companion';
    function matching() {
        var result = [], apps = $.NSWorkspace.sharedWorkspace.runningApplications;
        for (var index = 0; index < apps.count; index++) {
            var app = apps.objectAtIndex(index);
            if (ObjC.unwrap(app.bundleIdentifier) === identifier && !app.isTerminated) result.push(app);
        }
        return result;
    }
    function description(app) {
        return (ObjC.unwrap(app.localizedName) || 'Vale') + ' (PID ' + app.processIdentifier + '): ' + ObjC.unwrap(app.bundleURL.path);
    }
    if (argv[0] === 'list') return matching().map(description).join('\n') || 'No matching apps are running.';
    if (argv[0] === 'quit') {
        var apps = matching(), messages = [];
        apps.forEach(function(app) {
            if (!app.terminate) throw new Error('Quit was refused by ' + description(app) + '. No forced termination was attempted.');
            messages.push('Requested quit: ' + description(app));
        });
        var deadline = Date.now() + 15000;
        while (matching().length && Date.now() < deadline) $.NSThread.sleepForTimeInterval(0.25);
        if (matching().length) throw new Error('Some Vale copies are still running. Close them normally and retry.');
        return messages.join('\n') || 'No matching apps needed to quit.';
    }
    if (argv[0] === 'launch') {
        var target = ObjC.unwrap($.NSURL.fileURLWithPath(argv[1]).URLByResolvingSymlinksInPath.path);
        var deadline = Date.now() + 15000;
        while (Date.now() < deadline) {
            var apps = matching();
            for (var index = 0; index < apps.length; index++) {
                var actual = ObjC.unwrap(apps[index].bundleURL.URLByResolvingSymlinksInPath.path);
                if (actual === target) {
                    $.NSThread.sleepForTimeInterval(1);
                    if (!apps[index].isTerminated) return 'Running installed app: ' + description(apps[index]);
                }
            }
            $.NSThread.sleepForTimeInterval(0.25);
        }
        throw new Error('The installed app did not finish launching. macOS may require a normal security confirmation; no security setting was changed.');
    }
    throw new Error('Unknown app action.');
}
JXA
}

# Foundation refuses an existing destination; it never nests one bundle in another.
# Staging and the destination share a directory/volume, so the final move is a rename.
vale_move() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
    var error = Ref();
    if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(argv[0], argv[1], error)) {
        throw new Error('Could not move ' + argv[0] + ' to ' + argv[1] + '. The destination may exist or be unwritable.');
    }
}
JXA
}

vale_validate "$vale_source"
vale_source_version="$(vale_plist "$vale_source" CFBundleShortVersionString)"
vale_source_build="$(vale_plist "$vale_source" CFBundleVersion)"
[[ ! -L "$vale_install_dir" ]] || vale_fail "Refusing a symlinked installation directory: $vale_install_dir"
if [[ -e "$vale_install_dir" ]]; then
  [[ -d "$vale_install_dir" && -w "$vale_install_dir" ]] || vale_fail "Installation directory is not writable: $vale_install_dir"
else
  [[ -w "$HOME" ]] || vale_fail "Cannot create $vale_install_dir without additional permissions."
fi
[[ ! -L "$vale_target" ]] || vale_fail "Refusing a symlink at the installation target: $vale_target"
if [[ -e "$vale_target" && "$(vale_plist "$vale_target" CFBundleIdentifier 2>/dev/null || true)" != "$vale_identifier" ]]; then
  vale_fail "Another app occupies $vale_target; it will not be replaced."
fi

typeset -a vale_existing=()
for vale_root in "$HOME/Applications" /Applications; do
  [[ -d "$vale_root" ]] || continue
  vale_inventory="$(/usr/bin/find "$vale_root" -type d -iname '*.app' -prune -print0)" || vale_fail "Could not inventory installed apps under $vale_root."
  while IFS= read -r -d '' vale_bundle; do
    if [[ "$(vale_plist "$vale_bundle" CFBundleIdentifier 2>/dev/null || true)" == "$vale_identifier" ]]; then
      vale_existing+=("$vale_bundle")
      vale_log "Existing matching app: $vale_bundle"
      vale_old_version="$(vale_plist "$vale_bundle" CFBundleShortVersionString 2>/dev/null || true)"
      vale_old_build="$(vale_plist "$vale_bundle" CFBundleVersion 2>/dev/null || true)"
      if [[ "$vale_old_version" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
        is-at-least "$vale_old_version" "$vale_source_version" || vale_fail "Refusing to downgrade $vale_old_version to $vale_source_version: $vale_bundle"
        if [[ "$vale_old_version" == "$vale_source_version" && "$vale_old_build" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
          is-at-least "$vale_old_build" "$vale_source_build" || vale_fail "Refusing to replace newer build $vale_old_build with $vale_source_build: $vale_bundle"
        fi
      fi
      if [[ ! -w "${vale_bundle:h}" ]]; then
        if $vale_dry_run; then vale_log "Replacement would be blocked by an unwritable parent: $vale_bundle"
        else vale_fail "Cannot move this obsolete app without additional permissions: $vale_bundle"; fi
      fi
    fi
  done <<< "$vale_inventory"
done
vale_app_action list
if $vale_dry_run; then
  vale_log "Dry run: would install $vale_source at $vale_target."
  if (( ${#vale_existing} )); then vale_log "Replacement and obsolete-app cleanup require --replace. Found ${#vale_existing} matching app bundle(s)."; fi
  vale_log "No apps were quit, copied, moved or launched."
  exit 0
fi
if (( ${#vale_existing} )) && ! $vale_replace; then vale_fail "An installed Vale/Lilt copy already exists. Run with --replace to replace it explicitly."; fi

/bin/mkdir -p "$vale_install_dir"
vale_lock="$vale_install_dir/.vale-install.lock"
/bin/mkdir "$vale_lock" 2>/dev/null || vale_fail "Another installer may be active. Check $vale_lock before retrying."
vale_work=""
vale_installed=false
vale_confirmed=false
vale_backup=""
vale_cleanup() {
  local vale_exit=$?
  trap - EXIT INT TERM
  if $vale_installed && ! $vale_confirmed; then
    vale_log "Installation did not finish; restoring the previous app."
    if vale_app_action quit && vale_move "$vale_target" "$vale_work/failed-install.app"; then
      if [[ -n "$vale_backup" && -d "$vale_backup" ]]; then
        if vale_move "$vale_backup" "$vale_target"; then vale_log "Restored $vale_target"; else vale_log "Restore failed. Previous app is preserved at $vale_backup"; fi
      fi
    else
      vale_log "Could not roll back safely. The candidate and previous app are preserved; no app was force-quit."
    fi
  elif ! $vale_installed && [[ -n "$vale_backup" && -d "$vale_backup" && ! -e "$vale_target" ]]; then
    vale_move "$vale_backup" "$vale_target" || vale_log "Previous app is preserved at $vale_backup"
  fi
  if [[ -n "$vale_work" ]]; then
    if [[ -d "$vale_work/staged.app" ]]; then /bin/rm -rf "$vale_work/staged.app"; fi
    /bin/rmdir "$vale_work" 2>/dev/null || vale_log "Preserved recovery app(s): $vale_work"
  fi
  /bin/rmdir "$vale_lock" 2>/dev/null || true
  return "$vale_exit"
}
trap vale_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
vale_work="$(/usr/bin/mktemp -d "$vale_install_dir/.vale-install.XXXXXXXX")"
vale_log "Staging app before closing any running copy."
/usr/bin/ditto "$vale_source" "$vale_work/staged.app"
vale_validate "$vale_work/staged.app"
vale_trash="$HOME/.Trash"
[[ ! -L "$vale_trash" ]] || vale_fail "Refusing a symlinked Trash directory."
/bin/mkdir -p "$vale_trash"
[[ -w "$vale_trash" ]] || vale_fail "Trash is not writable; existing apps were preserved."
vale_app_action quit || vale_fail "No installation change was made because an app could not quit normally."
if [[ -e "$vale_target" ]]; then
  vale_backup="$vale_work/previous.app"
  vale_move "$vale_target" "$vale_backup"
fi
vale_move "$vale_work/staged.app" "$vale_target"
vale_installed=true
vale_validate "$vale_target"
vale_log "Opening $vale_target using normal macOS launch checks."
/usr/bin/open "$vale_target"
vale_app_action launch
vale_confirmed=true

# Only an installed, verified and running replacement authorizes obsolete cleanup.
vale_cleanup_failed=false
if [[ -n "$vale_backup" && -d "$vale_backup" ]]; then vale_existing+=("$vale_backup"); fi
for vale_bundle in "${vale_existing[@]}"; do
  [[ "$vale_bundle" != "$vale_target" && -d "$vale_bundle" && ! -L "$vale_bundle" ]] || continue
  [[ "$(vale_plist "$vale_bundle" CFBundleIdentifier 2>/dev/null || true)" == "$vale_identifier" ]] || { vale_log "Skipped a changed app bundle: $vale_bundle"; continue; }
  vale_name="${vale_bundle:t}"
  [[ "$vale_bundle" != "$vale_backup" ]] || vale_name="Vale (previous).app"
  vale_destination="$vale_trash/${vale_name%.[aA][pP][pP]} (replaced $(/bin/date +%Y%m%d-%H%M%S)).app"
  vale_counter=1
  while [[ -e "$vale_destination" || -L "$vale_destination" ]]; do
    vale_destination="$vale_trash/${vale_name%.[aA][pP][pP]} (replaced $(/bin/date +%Y%m%d-%H%M%S)-$vale_counter).app"
    (( vale_counter+=1 ))
  done
  if vale_move "$vale_bundle" "$vale_destination"; then vale_log "Moved obsolete app to Trash: $vale_bundle -> $vale_destination"
  else vale_log "Could not move obsolete app; preserved at $vale_bundle"; vale_cleanup_failed=true; fi
done
vale_log "Installed and running: $vale_target. Chats, settings, credentials and security permissions were preserved."
if $vale_cleanup_failed; then vale_fail "Vale is installed; one or more obsolete apps need manual cleanup at the preserved paths above."; fi
