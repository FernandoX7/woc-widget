#!/bin/bash
# Build the WoC Player Count menu bar app (no Xcode project needed).
#   ./build.sh           -> build + install the app to an Applications folder (one latest copy)
#   ./build.sh preview   -> build a windowed preview and launch it locally (screenshots; NOT installed)
#   WOC_NO_LAUNCH=1 ./build.sh preview -> compile/bundle preview without opening it (automation)
#   ./build.sh bundle    -> build a production app locally without installing or launching it
#   ./build.sh run       -> build + install, then relaunch the latest
#   ./build.sh check     -> type-check every app + view source without bundling/installing
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-app}"
case "$MODE" in
  app|bundle|preview|run|check) ;;
  *) echo "unknown mode: '$MODE' (use: app | bundle | preview | run | check)" >&2; exit 2 ;;
esac

APP_NAME="WoC Player Count"
BUILD_DIR="build"
BIN="$BUILD_DIR/WoCWidget"
APP_NAME_APP="$APP_NAME.app"
EXPECTED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)"
SYSTEM_INSTALL_DIR="/Applications"
INSTALL_DIR=""
INSTALL_FALLBACK=0
PREFLIGHT_ERROR=""
INSTALL_ERROR=""

destination_exists() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]]
}

preflight_install_directory() {
  local directory="$1"
  local destination="$directory/$APP_NAME_APP"
  local existing_bundle_id=""
  local writable_directory=""

  PREFLIGHT_ERROR=""
  if [[ -e "$directory" && ! -d "$directory" ]]; then
    PREFLIGHT_ERROR="the destination exists but is not a directory"
    return 1
  fi
  if ! mkdir -p "$directory" 2>/dev/null; then
    PREFLIGHT_ERROR="the Applications folder cannot be created"
    return 1
  fi
  if [[ ! -w "$directory" || ! -x "$directory" ]]; then
    PREFLIGHT_ERROR="the Applications folder is not writable"
    return 1
  fi

  if destination_exists "$destination"; then
    if [[ -L "$destination" || ! -d "$destination" ]]; then
      PREFLIGHT_ERROR="an unexpected item already exists at $destination"
      return 1
    fi
    if [[ ! -r "$destination/Contents/Info.plist" ]]; then
      PREFLIGHT_ERROR="the existing app cannot be identified safely"
      return 1
    fi
    existing_bundle_id="$(
      /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$destination/Contents/Info.plist" 2>/dev/null || true
    )"
    if [[ "$existing_bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
      PREFLIGHT_ERROR="the existing item has a different bundle identifier"
      return 1
    fi

    # Removing a backup requires write access to every directory in the old bundle. Check this
    # before staging or renaming anything so an administrator-owned copy is never partially
    # dismantled by a standard account.
    while IFS= read -r writable_directory; do
      if [[ ! -w "$writable_directory" || ! -x "$writable_directory" ]]; then
        PREFLIGHT_ERROR="the existing app cannot be replaced by this account"
        return 1
      fi
    done < <(find "$destination" -type d -print)
  fi

  return 0
}

select_install_directory() {
  local explicit=0
  local requested="$SYSTEM_INSTALL_DIR"
  local system_destination="$SYSTEM_INSTALL_DIR/$APP_NAME_APP"
  local user_install_dir="$HOME/Applications"
  local user_destination="$HOME/Applications/$APP_NAME_APP"
  local system_exists=0
  local user_exists=0
  local system_error=""

  if [[ "${WOC_INSTALL_DIR+x}" == "x" ]]; then
    explicit=1
    requested="${WOC_INSTALL_DIR}"
    if [[ -z "$requested" ]]; then
      echo "error: WOC_INSTALL_DIR cannot be empty" >&2
      return 2
    fi
  fi
  case "$requested" in
    /*) ;;
    *) echo "error: WOC_INSTALL_DIR must be an absolute path" >&2; return 2 ;;
  esac

  if [[ "$explicit" -eq 1 ]]; then
    if preflight_install_directory "$requested"; then
      INSTALL_DIR="$requested"
      return 0
    fi
    echo "error: cannot install to $requested: $PREFLIGHT_ERROR" >&2
    return 1
  fi

  destination_exists "$system_destination" && system_exists=1
  destination_exists "$user_destination" && user_exists=1

  if [[ "$system_exists" -eq 1 && "$user_exists" -eq 1 ]]; then
    echo "error: two installed copies already exist:" >&2
    echo "  $system_destination" >&2
    echo "  $user_destination" >&2
    echo "Keep one copy and remove the other in Finder, then run the installer again." >&2
    return 1
  fi

  # Preserve the established location. Moving an update to the other Applications folder would
  # strand the old copy and give LaunchServices two apps with the same bundle identifier.
  if [[ "$system_exists" -eq 1 ]]; then
    if preflight_install_directory "$SYSTEM_INSTALL_DIR"; then
      INSTALL_DIR="$SYSTEM_INSTALL_DIR"
      return 0
    fi
    echo "error: cannot safely replace $system_destination: $PREFLIGHT_ERROR" >&2
    echo "Remove that copy in Finder (or ask an administrator), then run the installer again." >&2
    return 1
  fi
  if [[ "$user_exists" -eq 1 ]]; then
    if preflight_install_directory "$user_install_dir"; then
      INSTALL_DIR="$user_install_dir"
      INSTALL_FALLBACK=1
      return 0
    fi
    echo "error: cannot safely replace $user_destination: $PREFLIGHT_ERROR" >&2
    echo "Remove that copy in Finder, then run the installer again." >&2
    return 1
  fi

  # With neither known destination occupied, prefer the system Applications folder.
  if preflight_install_directory "$SYSTEM_INSTALL_DIR"; then
    INSTALL_DIR="$SYSTEM_INSTALL_DIR"
    return 0
  fi
  system_error="$PREFLIGHT_ERROR"

  # We may fall back only when /Applications can be searched well enough to prove the system app
  # is absent. This prevents an inaccessible directory from hiding a duplicate installation.
  if [[ ! -d "$SYSTEM_INSTALL_DIR" || ! -x "$SYSTEM_INSTALL_DIR" ]]; then
    echo "error: cannot inspect $SYSTEM_INSTALL_DIR safely: $system_error" >&2
    return 1
  fi

  if preflight_install_directory "$user_install_dir"; then
    INSTALL_DIR="$user_install_dir"
    INSTALL_FALLBACK=1
    return 0
  fi

  echo "error: neither $SYSTEM_INSTALL_DIR nor $HOME/Applications is usable: $PREFLIGHT_ERROR" >&2
  return 1
}

# Validate and select an install destination before spending time compiling. Preview, bundle, and
# check modes intentionally remain independent of installation permissions.
if [[ "$MODE" == "app" || "$MODE" == "run" ]]; then
  select_install_directory
fi

# Every Swift source (WoCKit logic + App + Views) compiles into one flat module.
# `find` (vs a bash-4 globstar) keeps this portable to the stock macOS /bin/bash 3.2.
SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(find Sources -name '*.swift' -type f | sort)

mkdir -p "$BUILD_DIR"

# -target pins the deployment floor to macOS 14 (matches Info.plist/Package.swift) so the binary's
# `minos` can't silently drift up with a future SDK. -swift-version 5 pins the language mode to the
# same value Package.swift declares (swiftLanguageModes: [.v5]) so the swiftc and SwiftPM builds
# can't diverge.
TARGET="$(uname -m)-apple-macos14.0"
echo "› Compiling ($MODE, ${#SRCS[@]} files)…"
if [[ "$MODE" == "check" ]]; then
  swiftc -typecheck -parse-as-library -target "$TARGET" -swift-version 5 "${SRCS[@]}"
  echo "✓ Type-check complete (no bundle installed)"
  exit 0
elif [[ "$MODE" == "preview" ]]; then
  swiftc -O -parse-as-library -target "$TARGET" -swift-version 5 -DPREVIEW "${SRCS[@]}" -o "$BIN"
else
  swiftc -O -parse-as-library -target "$TARGET" -swift-version 5 "${SRCS[@]}" -o "$BIN"
fi

APP="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
if [[ "$MODE" == "preview" ]]; then
  # Keep LaunchServices/TCC identity separate from an installed production copy. Preview already
  # uses isolated defaults and no-op side effects; the bundle suffix closes the remaining path by
  # which `open` could select or attribute work to the production application.
  PREVIEW_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist").preview"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PREVIEW_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
cp "$BIN" "$APP/Contents/MacOS/WoCWidget"
chmod +x "$APP/Contents/MacOS/WoCWidget"

# Compile the String Catalog into en.lproj/Localizable.strings and bundle it. (xcstringstool is
# a separate tool from swiftc — the .xcstrings is NOT a swiftc input. Without this step the app
# falls back to raw keys at runtime.) String(localized:)/LocalizedStringKey resolve from here.
if [ -f Resources/Localizable.xcstrings ]; then
  STRINGS_BUILD="$BUILD_DIR/strings"
  rm -rf "$STRINGS_BUILD"; mkdir -p "$STRINGS_BUILD"
  xcrun xcstringstool compile --output-directory "$STRINGS_BUILD" Resources/Localizable.xcstrings
  cp -R "$STRINGS_BUILD"/*.lproj "$APP/Contents/Resources/"
fi

# App icon (see scripts/make-icon.sh to regenerate)
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Keep the license, provider credits, and app privacy disclosure with every bundle, including local
# builds copied outside this repository. Public release construction also places them at DMG root.
for notice in LICENSE CREDITS.md PRIVACY.md; do
  [[ -s "$notice" ]] || { echo "error: required notice is missing: $notice" >&2; exit 1; }
  cp "$notice" "$APP/Contents/Resources/"
done

# Ad-hoc sign to seal the locally built bundle and satisfy macOS signed-code requirements. (`--deep`
# is deprecated since macOS 13 and a no-op here anyway — the bundle has no nested Mach-O.) Ad-hoc
# signing does not provide a verified developer identity or notarization, so failures are surfaced
# rather than allowing an unsigned bundle to replace the installed copy.
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "✓ Built: $APP"

# The real menu-bar app lives in an Applications folder, so there is exactly ONE installed copy and
# the build/ bundle never lingers as a Spotlight/Launchpad duplicate. /Applications is preferred;
# a standard account falls back to ~/Applications only when no system copy exists. WOC_INSTALL_DIR
# can select another absolute folder. Preview builds are local and NEVER installed.

install_bundle() {
  local directory="$1"
  local destination="$directory/$APP_NAME_APP"
  local suffix="$$"
  local staged="$directory/.woc-player-count.installing.$suffix"
  local backup="$directory/.woc-player-count.backup.$suffix"
  local had_existing=0

  INSTALL_ERROR=""
  if ! preflight_install_directory "$directory"; then
    INSTALL_ERROR="$PREFLIGHT_ERROR"
    return 1
  fi
  while destination_exists "$staged" || destination_exists "$backup"; do
    suffix="$suffix.$RANDOM"
    staged="$directory/.woc-player-count.installing.$suffix"
    backup="$directory/.woc-player-count.backup.$suffix"
  done

  # Stage on the destination volume first. The installed copy remains untouched if copying,
  # signing verification, disk space, or permissions fail.
  if ! /usr/bin/ditto "$APP" "$staged"; then
    rm -rf "$staged" 2>/dev/null || true
    INSTALL_ERROR="the new app could not be staged"
    return 1
  fi
  if ! codesign --verify --strict --verbose=2 "$staged"; then
    rm -rf "$staged" 2>/dev/null || true
    INSTALL_ERROR="the staged app failed code-signature verification"
    return 1
  fi

  if destination_exists "$destination"; then
    if ! mv "$destination" "$backup"; then
      rm -rf "$staged" 2>/dev/null || true
      INSTALL_ERROR="the existing app could not be moved aside safely"
      return 1
    fi
    had_existing=1
  fi

  if ! mv "$staged" "$destination"; then
    if [[ "$had_existing" -eq 1 ]] && ! mv "$backup" "$destination"; then
      echo "error: automatic rollback failed; the previous app remains at $backup" >&2
    fi
    rm -rf "$staged" 2>/dev/null || true
    INSTALL_ERROR="the staged app could not be activated"
    return 1
  fi

  if ! codesign --verify --strict --verbose=2 "$destination"; then
    if [[ "$had_existing" -eq 1 ]]; then
      if mv "$destination" "$staged"; then
        if mv "$backup" "$destination"; then
          rm -rf "$staged" 2>/dev/null || true
        else
          echo "error: automatic rollback failed; the new app is at $staged" >&2
          echo "error: the previous app remains at $backup" >&2
        fi
      else
        echo "error: automatic rollback failed; the new app remains at $destination" >&2
        echo "error: the previous app remains at $backup" >&2
      fi
    else
      rm -rf "$destination" 2>/dev/null || true
    fi
    INSTALL_ERROR="the installed app failed code-signature verification"
    return 1
  fi

  if [[ "$had_existing" -eq 1 ]] && ! rm -rf "$backup"; then
    echo "warning: the previous hidden backup could not be removed: $backup" >&2
  fi
  if ! rm -rf "$APP"; then
    echo "warning: the local build copy could not be removed: $APP" >&2
  fi
  INSTALLED="$destination"
  return 0
}

if [[ "$MODE" == "preview" ]]; then
  if [[ "${WOC_NO_LAUNCH:-0}" == "1" ]]; then
    echo "✓ Preview bundle kept local (launch skipped): $APP"
  else
    echo "› Launching preview (local, not installed)…"
    # Force a distinct instance so multiple deterministic preview destinations can be inspected.
    open -n "$APP"
  fi
elif [[ "$MODE" == "bundle" ]]; then
  echo "✓ Production bundle kept local (not installed): $APP"
else
  # The destination was selected before compilation. Installation failures are terminal: opening a
  # build/ copy would make a failed install look successful and create an ambiguous app identity.
  if install_bundle "$INSTALL_DIR"; then
    if [[ "$INSTALL_FALLBACK" -eq 1 ]]; then
      echo "✓ Installed for this user: $INSTALLED"
    else
      echo "✓ Installed: $INSTALLED"
    fi
  else
    echo "error: could not install to $INSTALL_DIR: $INSTALL_ERROR" >&2
    exit 1
  fi
  if [[ "$MODE" == "run" ]]; then
    echo "› Relaunching the latest…"
    pkill -f "$APP_NAME_APP/Contents/MacOS/WoCWidget" 2>/dev/null || true
    sleep 1
    open "$INSTALLED"
  fi
fi
