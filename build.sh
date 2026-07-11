#!/bin/bash
# Build the WoC Player Count menu bar app (no Xcode project needed).
#   ./build.sh           -> build + install the app to /Applications (one copy, always latest)
#   ./build.sh preview   -> build a windowed preview and launch it locally (screenshots; NOT installed)
#   WOC_NO_LAUNCH=1 ./build.sh preview -> compile/bundle preview without opening it (automation)
#   ./build.sh bundle    -> build a production app locally without installing or launching it
#   ./build.sh run       -> build + install to /Applications, then relaunch the latest
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

# Ad-hoc sign so macOS launches it without fuss. (`--deep` is deprecated since macOS 13 and a
# no-op here anyway — the bundle has no nested Mach-O. Signing is load-bearing for the notification
# prompt and a stable Gatekeeper/TCC
# identity, so a failure is surfaced rather than hidden. An unsigned bundle must never replace the
# installed copy: doing so can strand notification permission under a different identity and makes
# the successful-looking build materially unusable.)
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "✓ Built: $APP"

# The real menu-bar app always lives in /Applications, so there is exactly ONE copy (the latest)
# and the build/ bundle never lingers as a Spotlight/Launchpad duplicate. The preview build is a
# throwaway windowed binary (synthetic data) for screenshots — it is NEVER installed; it just
# launches in place. (build.sh stays the single build path: compile → bundle → codesign → install.)
APP_NAME_APP="$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME_APP"

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
  # Move (not copy) the freshly-signed bundle into /Applications so the build/ copy can't linger as
  # a duplicate. Ad-hoc signatures are path-independent, so the move keeps the signature valid.
  if rm -rf "$INSTALLED" 2>/dev/null && mv "$APP" "$INSTALLED"; then
    echo "✓ Installed: $INSTALLED"
  else
    echo "⚠ Could not install to /Applications — leaving the build at $APP" >&2
    INSTALLED="$APP"
  fi
  if [[ "$MODE" == "run" ]]; then
    echo "› Relaunching the latest…"
    pkill -f "$APP_NAME_APP/Contents/MacOS/WoCWidget" 2>/dev/null || true
    sleep 1
    open "$INSTALLED"
  fi
fi
