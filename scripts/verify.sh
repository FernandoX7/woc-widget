#!/bin/bash
# Deterministic production verification for the WoC menu-bar app.
#
# This intentionally does not install over /Applications or reuse an arbitrary running copy. It
# compiles both entry points, builds a fresh local production bundle, launches that exact binary
# with its popover closed, and measures process CPU time + RSS over a bounded window.
#
# Resource thresholds can be tuned for a known machine:
#   WOC_VERIFY_CPU_MAX_PERCENT=2.0
#   WOC_VERIFY_RSS_MAX_MB=250
#   WOC_VERIFY_RSS_GROWTH_MAX_MB=32
#   WOC_VERIFY_WARMUP_SECONDS=15
#   WOC_VERIFY_SAMPLE_SECONDS=15
#   WOC_VERIFY_SAMPLE_INTERVAL=1
#
# Set WOC_SKIP_RESOURCE_CHECK=1 only in an environment that cannot launch AppKit processes. The
# skip is explicit and loudly reported; compilation/tests/bundle validation still run.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=lib/verify_helpers.sh
source scripts/lib/verify_helpers.sh

SOURCE_INFO="Info.plist"
APP="build/WoC Player Count.app"
APP_BIN=""
EXPECTED_BUNDLE_ID="io.github.fernandox7.wocplayercount"
EXPECTED_EXECUTABLE="WoCWidget"
EXPECTED_MIN_SYSTEM_VERSION="14.0"
CPU_MAX="${WOC_VERIFY_CPU_MAX_PERCENT:-2.0}"
RSS_MAX_MB="${WOC_VERIFY_RSS_MAX_MB:-250}"
RSS_GROWTH_MAX_MB="${WOC_VERIFY_RSS_GROWTH_MAX_MB:-32}"
WARMUP_SECONDS="${WOC_VERIFY_WARMUP_SECONDS:-15}"
SAMPLE_SECONDS="${WOC_VERIFY_SAMPLE_SECONDS:-15}"
SAMPLE_INTERVAL="${WOC_VERIFY_SAMPLE_INTERVAL:-1}"
VERIFY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/woc-verify.XXXXXX")"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    local attempts=0
    while kill -0 "$APP_PID" 2>/dev/null && [[ "$attempts" -lt 20 ]]; do
      sleep 0.1
      attempts=$((attempts + 1))
    done
    if kill -0 "$APP_PID" 2>/dev/null; then kill -9 "$APP_PID" 2>/dev/null || true; fi
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$VERIFY_TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

heading() {
  echo
  echo "── $1 ──"
}

require_number() {
  local name="$1"
  local value="$2"
  is_nonnegative_number "$value" || {
    echo "error: $name must be a non-negative number (got '$value')" >&2
    exit 2
  }
}

require_integer() {
  local name="$1"
  local value="$2"
  is_positive_integer "$value" || {
    echo "error: $name must be a positive integer (got '$value')" >&2
    exit 2
  }
}

require_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  [[ "$actual" == "$expected" ]] || {
    echo "error: $label must be '$expected' (got '$actual')" >&2
    exit 1
  }
}

plist_value() {
  local key="$1"
  local plist="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist"
}

require_number WOC_VERIFY_CPU_MAX_PERCENT "$CPU_MAX"
require_number WOC_VERIFY_RSS_MAX_MB "$RSS_MAX_MB"
require_number WOC_VERIFY_RSS_GROWTH_MAX_MB "$RSS_GROWTH_MAX_MB"
require_integer WOC_VERIFY_WARMUP_SECONDS "$WARMUP_SECONDS"
require_integer WOC_VERIFY_SAMPLE_SECONDS "$SAMPLE_SECONDS"
require_integer WOC_VERIFY_SAMPLE_INTERVAL "$SAMPLE_INTERVAL"
if [[ "$SAMPLE_SECONDS" -lt "$SAMPLE_INTERVAL" ]]; then
  echo "error: WOC_VERIFY_SAMPLE_SECONDS must be >= WOC_VERIFY_SAMPLE_INTERVAL" >&2
  exit 2
fi

for tool in swift swiftc xcrun codesign plutil ps awk date tr sed sort mktemp find grep lipo uname python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: required command '$tool' is unavailable" >&2
    exit 127
  }
done
xcrun --find vtool >/dev/null 2>&1 || {
  echo "error: vtool is unavailable; select a full Xcode installation" >&2
  exit 127
}

SOURCE_BUNDLE_ID="$(plist_value CFBundleIdentifier "$SOURCE_INFO")"
SOURCE_EXECUTABLE="$(plist_value CFBundleExecutable "$SOURCE_INFO")"
SOURCE_LSUIELEMENT="$(plist_value LSUIElement "$SOURCE_INFO")"
SOURCE_MIN_SYSTEM_VERSION="$(plist_value LSMinimumSystemVersion "$SOURCE_INFO")"
SOURCE_DEVELOPMENT_REGION="$(plist_value CFBundleDevelopmentRegion "$SOURCE_INFO")"
APP_BIN="$APP/Contents/MacOS/$SOURCE_EXECUTABLE"

heading "script checks"
/bin/bash -n build.sh scripts/verify.sh scripts/lib/verify_helpers.sh \
  scripts/tests/verify_helpers_test.sh scripts/release.sh scripts/check-source-invariants.sh
scripts/tests/verify_helpers_test.sh

heading "source architecture invariants"
plutil -lint "$SOURCE_INFO" >/dev/null
require_equal "source bundle identifier" "$EXPECTED_BUNDLE_ID" "$SOURCE_BUNDLE_ID"
require_equal "source executable" "$EXPECTED_EXECUTABLE" "$SOURCE_EXECUTABLE"
require_equal "source LSUIElement" "true" "$SOURCE_LSUIELEMENT"
require_equal "source minimum system version" "$EXPECTED_MIN_SYSTEM_VERSION" \
  "$SOURCE_MIN_SYSTEM_VERSION"
[[ -f Resources/Localizable.xcstrings ]] || {
  echo "error: source String Catalog is missing" >&2
  exit 1
}

scripts/check-source-invariants.sh
scripts/check-localizations.py

WIDGETKIT_IMPORTS="$(
  find Sources -name '*.swift' -type f -exec grep -HnE \
    '^[[:space:]]*(@_exported[[:space:]]+)?import([[:space:]]+(class|enum|func|protocol|struct|typealias|var))?[[:space:]]+WidgetKit([[:space:].]|$)' \
    {} + || true
)"
if [[ -n "$WIDGETKIT_IMPORTS" ]]; then
  echo "error: WidgetKit imports are not allowed in this menu-bar-only app:" >&2
  echo "$WIDGETKIT_IMPORTS" >&2
  exit 1
fi

WIDGETKIT_PROJECT_REFERENCES="$(
  find . \( -path './.git' -o -path './.build' -o -path './build' \) -prune -o \
    -name project.pbxproj -type f \
    -exec grep -Hn 'WidgetKit.framework' {} + || true
  grep -nE '[.]linkedFramework[[:space:]]*[(][[:space:]]*"WidgetKit"' Package.swift || true
)"
if [[ -n "$WIDGETKIT_PROJECT_REFERENCES" ]]; then
  echo "error: WidgetKit target references are not allowed:" >&2
  echo "$WIDGETKIT_PROJECT_REFERENCES" >&2
  exit 1
fi
echo "✓ production identity, deployment floor, localization source, and menu-bar-only scope"

heading "WoCKit tests"
swift test

heading "all-source typecheck"
./build.sh check

heading "preview compile + bundle"
WOC_NO_LAUNCH=1 ./build.sh preview
[[ -x "$APP_BIN" ]] || { echo "error: preview binary was not produced" >&2; exit 1; }
require_equal "preview bundle identifier" "$SOURCE_BUNDLE_ID.preview" \
  "$(plist_value CFBundleIdentifier "$APP/Contents/Info.plist")"
codesign --verify --strict --verbose=2 "$APP"

heading "optimized production bundle"
./build.sh bundle
[[ -x "$APP_BIN" ]] || { echo "error: production binary was not produced" >&2; exit 1; }
plutil -lint "$APP/Contents/Info.plist" >/dev/null

BUNDLE_INFO="$APP/Contents/Info.plist"
require_equal "bundle identifier" "$SOURCE_BUNDLE_ID" \
  "$(plist_value CFBundleIdentifier "$BUNDLE_INFO")"
require_equal "bundle executable" "$SOURCE_EXECUTABLE" \
  "$(plist_value CFBundleExecutable "$BUNDLE_INFO")"
require_equal "bundle LSUIElement" "$SOURCE_LSUIELEMENT" \
  "$(plist_value LSUIElement "$BUNDLE_INFO")"
require_equal "bundle minimum system version" "$SOURCE_MIN_SYSTEM_VERSION" \
  "$(plist_value LSMinimumSystemVersion "$BUNDLE_INFO")"

LOCALIZATION_FILE="$APP/Contents/Resources/$SOURCE_DEVELOPMENT_REGION.lproj/Localizable.strings"
[[ -s "$LOCALIZATION_FILE" ]] || {
  echo "error: compiled localization is missing or empty: $LOCALIZATION_FILE" >&2
  exit 1
}
plutil -lint "$LOCALIZATION_FILE" >/dev/null

for notice in LICENSE CREDITS.md PRIVACY.md; do
  [[ -s "$APP/Contents/Resources/$notice" ]] || {
    echo "error: bundled notice is missing or empty: $notice" >&2
    exit 1
  }
done

if find "$APP/Contents" -type d -name '*.appex' -print -quit | grep -q .; then
  echo "error: application extensions are not allowed in the menu-bar-only bundle" >&2
  exit 1
fi

HOST_ARCH="$(uname -m)"
BINARY_ARCHS="$(lipo -archs "$APP_BIN")"
case " $BINARY_ARCHS " in
  *" $HOST_ARCH "*) ;;
  *)
    echo "error: production binary does not contain the host architecture $HOST_ARCH" >&2
    exit 1
    ;;
esac
for arch in $BINARY_ARCHS; do
  case "$arch" in
    arm64|x86_64) ;;
    *) echo "error: unsupported production binary architecture '$arch'" >&2; exit 1 ;;
  esac
done

BUILD_METADATA="$(xcrun vtool -show-build "$APP_BIN")"
BINARY_PLATFORMS="$(printf '%s\n' "$BUILD_METADATA" | awk '$1 == "platform" { print $2 }' | sort -u)"
BINARY_MIN_VERSIONS="$(printf '%s\n' "$BUILD_METADATA" | awk '$1 == "minos" { print $2 }' | sort -u)"
require_equal "binary platform" "MACOS" "$BINARY_PLATFORMS"
require_equal "binary minimum system version" "$SOURCE_MIN_SYSTEM_VERSION" "$BINARY_MIN_VERSIONS"
codesign --verify --strict --verbose=2 "$APP"
echo "✓ bundle metadata, localization, architecture ($BINARY_ARCHS), and minos are valid"

if [[ "${WOC_SKIP_RESOURCE_CHECK:-0}" == "1" ]]; then
  heading "resource smoke check"
  echo "SKIPPED explicitly (WOC_SKIP_RESOURCE_CHECK=1)"
  echo
  echo "✓ verification complete (resource check skipped)"
  exit 0
fi

heading "closed-popover CPU + memory smoke check"
echo "Launching exact bundle binary: $APP_BIN"
mkdir -p "$VERIFY_TMP/home"
HOME="$VERIFY_TMP/home" CFFIXED_USER_HOME="$VERIFY_TMP/home" \
  "$APP_BIN" >"$VERIFY_TMP/app.stdout.log" 2>"$VERIFY_TMP/app.stderr.log" &
APP_PID=$!

sleep "$WARMUP_SECONDS"
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "error: app exited during the ${WARMUP_SECONDS}s warmup" >&2
  [[ ! -s "$VERIFY_TMP/app.stderr.log" ]] || sed -n '1,80p' "$VERIFY_TMP/app.stderr.log" >&2
  exit 1
fi

CPU_START_RAW="$(ps -p "$APP_PID" -o time= | tr -d '[:space:]')"
CPU_START="$(cpu_time_to_seconds "$CPU_START_RAW")"
START_EPOCH="$(date +%s)"
RSS_SAMPLES="$VERIFY_TMP/rss-kb.txt"
SAMPLE_COUNT=$(((SAMPLE_SECONDS + SAMPLE_INTERVAL - 1) / SAMPLE_INTERVAL + 1))
sample=0

while [[ "$sample" -lt "$SAMPLE_COUNT" ]]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "error: app exited during resource sampling" >&2
    [[ ! -s "$VERIFY_TMP/app.stderr.log" ]] || sed -n '1,80p' "$VERIFY_TMP/app.stderr.log" >&2
    exit 1
  fi
  RSS_KB="$(ps -p "$APP_PID" -o rss= | tr -d '[:space:]')"
  is_positive_integer "$RSS_KB" || {
    echo "error: could not read a valid RSS sample for pid $APP_PID (got '$RSS_KB')" >&2
    exit 1
  }
  echo "$RSS_KB" >>"$RSS_SAMPLES"
  sample=$((sample + 1))
  if [[ "$sample" -lt "$SAMPLE_COUNT" ]]; then sleep "$SAMPLE_INTERVAL"; fi
done

END_EPOCH="$(date +%s)"
if ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "error: app exited at the end of resource sampling" >&2
  exit 1
fi
CPU_END_RAW="$(ps -p "$APP_PID" -o time= | tr -d '[:space:]')"
CPU_END="$(cpu_time_to_seconds "$CPU_END_RAW")"
ELAPSED=$((END_EPOCH - START_EPOCH))
CPU_AVERAGE="$(cpu_average_percent "$CPU_START" "$CPU_END" "$ELAPSED")"

read -r RSS_COUNT RSS_MIN_KB RSS_PEAK_KB RSS_FIRST_KB RSS_LAST_KB \
  <<<"$(summarize_integer_samples <"$RSS_SAMPLES")"
RSS_MIN_MB="$(kb_to_mb "$RSS_MIN_KB")"
RSS_PEAK_MB="$(kb_to_mb "$RSS_PEAK_KB")"
RSS_FIRST_MB="$(kb_to_mb "$RSS_FIRST_KB")"
RSS_LAST_MB="$(kb_to_mb "$RSS_LAST_KB")"
RSS_GROWTH_KB="$(edge_average_growth 3 <"$RSS_SAMPLES")"
RSS_GROWTH_MB="$(kb_to_mb "$RSS_GROWTH_KB")"

echo "pid:             $APP_PID"
echo "measurement:     ${ELAPSED}s after ${WARMUP_SECONDS}s warmup"
echo "CPU average:     ${CPU_AVERAGE}% (limit ${CPU_MAX}%)"
echo "RSS samples:     $RSS_COUNT"
echo "RSS first/last:  ${RSS_FIRST_MB} MB / ${RSS_LAST_MB} MB"
echo "RSS min/peak:    ${RSS_MIN_MB} MB / ${RSS_PEAK_MB} MB (limit ${RSS_MAX_MB} MB)"
echo "RSS edge growth: ${RSS_GROWTH_MB} MB (3-sample averages; limit ${RSS_GROWTH_MAX_MB} MB)"

FAILED=0
if number_greater_than "$CPU_AVERAGE" "$CPU_MAX"; then
  echo "error: average closed-popover CPU exceeded its limit" >&2
  FAILED=1
fi
if number_greater_than "$RSS_PEAK_MB" "$RSS_MAX_MB"; then
  echo "error: peak RSS exceeded its limit" >&2
  FAILED=1
fi
if number_greater_than "$RSS_GROWTH_MB" "$RSS_GROWTH_MAX_MB"; then
  echo "error: RSS growth exceeded its limit" >&2
  FAILED=1
fi
if [[ "$FAILED" -ne 0 ]]; then
  if [[ -s "$VERIFY_TMP/app.stderr.log" ]]; then
    echo "app stderr (first 80 lines):" >&2
    sed -n '1,80p' "$VERIFY_TMP/app.stderr.log" >&2
  fi
  exit 1
fi

echo
echo "✓ verification complete"
echo "Note: MenuBarExtra cannot be opened/closed programmatically; manually repeat the CPU check"
echo "after an open→close cycle when changing scene, badge, footer, or animation code."
