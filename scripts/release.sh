#!/bin/bash
# Produce universal, hardened-runtime Developer ID release artifacts and notarize them.
#
# Required:
#   DEVELOPER_ID_APPLICATION="Developer ID Application: …"
#
# Typical:
#   VERSION=1.1.0 BUILD_NUMBER=42 NOTARY_PROFILE=woc-notary ./scripts/release.sh
#
# NOTARY_PROFILE is the keychain profile created with `xcrun notarytool store-credentials`.
# An intentionally unnotarized development artifact additionally requires
# ALLOW_UNNOTARIZED_RELEASE=1 and must never be published.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=lib/verify_helpers.sh
source scripts/lib/verify_helpers.sh

for tool in awk swiftc lipo codesign ditto hdiutil xcrun find sort mktemp shasum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: required command '$tool' is unavailable" >&2
    exit 127
  }
done
xcrun --find xcstringstool >/dev/null 2>&1 || {
  echo "error: xcstringstool is unavailable; select a full Xcode installation" >&2
  exit 127
}
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun --find notarytool >/dev/null 2>&1 || {
    echo "error: notarytool is unavailable; select a full Xcode installation" >&2
    exit 127
  }
elif [[ "${ALLOW_UNNOTARIZED_RELEASE:-0}" != "1" ]]; then
  echo "error: NOTARY_PROFILE is required for a publishable release" >&2
  echo "       set ALLOW_UNNOTARIZED_RELEASE=1 only for an intentional local test" >&2
  exit 2
fi

SOURCE_INFO="Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$SOURCE_INFO")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_INFO")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SOURCE_INFO")"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_INFO")}"

is_valid_marketing_version "$VERSION" || {
  echo "error: VERSION must contain two or three numeric components" >&2
  exit 2
}
is_valid_build_number "$BUILD_NUMBER" || {
  echo "error: BUILD_NUMBER must be an integer from 1 through 9999" >&2
  exit 2
}

require_developer_id_signature() {
  local path="$1"
  local authority
  authority="$(codesign --display --verbose=4 "$path" 2>&1 | awk '
    /^Authority=/ && authority == "" {
      sub(/^Authority=/, "")
      authority = $0
    }
    END { print authority }
  ')"
  case "$authority" in
    "Developer ID Application:"*) ;;
    *)
      echo "error: expected a Developer ID Application signature on '$path'" >&2
      exit 1
      ;;
  esac
}

IDENTITY="${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to a Developer ID Application identity}"
OUT="$PWD/release"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/woc-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ZIP="$OUT/$APP_NAME-$VERSION.zip"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
CHECKSUMS="$OUT/$APP_NAME-$VERSION-SHA256SUMS.txt"

SRCS=()
while IFS= read -r file; do SRCS+=("$file"); done < <(find Sources -name '*.swift' -type f | sort)

mkdir -p "$OUT" "$WORK/bin"
rm -f "$DMG" "$ZIP" "$CHECKSUMS"

for arch in arm64 x86_64; do
  echo "› Compiling $arch…"
  swiftc -O -parse-as-library -target "$arch-apple-macos14.0" -swift-version 5 \
    "${SRCS[@]}" -o "$WORK/bin/WoCWidget-$arch"
done

APP="$WORK/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$WORK/bin/WoCWidget-arm64" "$WORK/bin/WoCWidget-x86_64" \
  -output "$APP/Contents/MacOS/$EXECUTABLE"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/$EXECUTABLE"
cp "$SOURCE_INFO" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

[[ -f Resources/Localizable.xcstrings ]] || {
  echo "error: Resources/Localizable.xcstrings is missing" >&2
  exit 1
}
mkdir -p "$WORK/strings"
xcrun xcstringstool compile --output-directory "$WORK/strings" Resources/Localizable.xcstrings
cp -R "$WORK/strings"/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for notice in LICENSE CREDITS.md PRIVACY.md; do
  [[ -s "$notice" ]] || { echo "error: required notice is missing: $notice" >&2; exit 1; }
  cp "$notice" "$APP/Contents/Resources/"
done

echo "› Signing $BUNDLE_ID with hardened runtime…"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
require_developer_id_signature "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "› Submitting the signed app for notarization…"
  xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  # Recreate the archive after stapling. The ZIP container is not itself code signed or stapled;
  # it preserves the signed, notarized app and its attached ticket.
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
else
  echo "⚠ NOTARY_PROFILE is unset; the signed app was not notarized."
fi

DMG_ROOT="$WORK/dmg"
mkdir -p "$DMG_ROOT"
# ditto preserves bundle metadata, including the app's stapled ticket, in the DMG staging tree.
ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cp LICENSE CREDITS.md PRIVACY.md "$DMG_ROOT/"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_ROOT" \
  -ov -format UDZO "$DMG"

echo "› Signing the disk image with Developer ID…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
require_developer_id_signature "$DMG"
hdiutil verify -quiet "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "› Submitting the signed disk image for notarization…"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"
  hdiutil verify -quiet "$DMG"
fi

(
  cd "$OUT"
  shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" \
    > "$(basename "$CHECKSUMS")"
)

echo "✓ Release artifacts:"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "  $ZIP (contains the Developer ID-signed, notarized, stapled app)"
  echo "  $DMG (Developer ID-signed, notarized, stapled, and validated)"
else
  echo "  $ZIP (contains the Developer ID-signed app; not notarized)"
  echo "  $DMG (Developer ID-signed; not notarized or stapled)"
fi
echo "  $CHECKSUMS (SHA-256 checksums)"
