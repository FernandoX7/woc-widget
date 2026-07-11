#!/bin/bash
# Friendly source-install entry point. This performs only local compilation and ad-hoc signing;
# it never reads an Apple account, distribution certificate, or notarization credential.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-install}"
case "$MODE" in
  install|--check) ;;
  *) echo "usage: ./install.sh [--check]" >&2; exit 2 ;;
esac

fail() {
  echo "error: $1" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "WoC Player Count requires macOS"

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
case "$MACOS_MAJOR" in
  ''|*[!0-9]*) fail "could not determine the macOS version" ;;
esac
[[ "$MACOS_MAJOR" -ge 14 ]] || fail "macOS 14 or newer is required (found $MACOS_VERSION)"

for tool in swiftc xcodebuild xcrun codesign open; do
  command -v "$tool" >/dev/null 2>&1 || fail "required developer tool '$tool' is unavailable"
done

SELECTED_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$SELECTED_DEVELOPER_DIR" ]] || ! xcrun --find xcstringstool >/dev/null 2>&1; then
  cat >&2 <<'MESSAGE'
error: a full Xcode installation must be selected.

Install Xcode from the Mac App Store, open it once to finish setup, then run:
  sudo xcode-select --switch /Applications/Xcode.app

The standalone Command Line Tools do not include xcstringstool, which this app needs to compile
its localized interface.
MESSAGE
  exit 1
fi

XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>/dev/null)" \
  || fail "Xcode is not ready; open it once to finish setup, then rerun this installer"
XCODE_VERSION="$(printf '%s\n' "$XCODE_VERSION_OUTPUT" | awk 'NR == 1 && $1 == "Xcode" { print $2 }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
case "$XCODE_MAJOR" in
  ''|*[!0-9]*) fail "could not determine the selected Xcode version" ;;
esac
[[ "$XCODE_MAJOR" -ge 16 ]] \
  || fail "Xcode 16 or newer is required (found Xcode $XCODE_VERSION)"

if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  fail "Xcode setup is incomplete; open Xcode once to finish setup, then rerun this installer"
fi

[[ -f Info.plist && -d Sources && -f Resources/Localizable.xcstrings ]] \
  || fail "run this script from a complete WoC Player Count repository checkout"

echo "✓ macOS $MACOS_VERSION"
echo "✓ Xcode $XCODE_VERSION"
echo "✓ Full Xcode tools selected at $SELECTED_DEVELOPER_DIR"
echo "✓ No paid Apple Developer account is required for this local build"

if [[ "$MODE" == "--check" ]]; then
  echo "✓ Local-install prerequisites are ready"
  exit 0
fi

echo
echo "› Building, installing, and launching WoC Player Count locally…"
./build.sh run
