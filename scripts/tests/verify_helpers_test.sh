#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# shellcheck source=../lib/verify_helpers.sh
source scripts/lib/verify_helpers.sh

fail() {
  echo "verify helper test failed: $*" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label (expected '$expected', got '$actual')"
}

assert_equal "0.030" "$(cpu_time_to_seconds '0:00.03')" "fractional ps time"
assert_equal "62.500" "$(cpu_time_to_seconds '1:02.50')" "minute ps time"
assert_equal "3723.250" "$(cpu_time_to_seconds '1:02:03.25')" "hour ps time"
assert_equal "93784.000" "$(cpu_time_to_seconds '1-02:03:04')" "day ps time"
if cpu_time_to_seconds 'not-a-time' >/dev/null 2>&1; then fail "invalid ps time accepted"; fi
if cpu_time_to_seconds '0:61.0' >/dev/null 2>&1; then fail "out-of-range ps time accepted"; fi
assert_equal "2.00" "$(cpu_average_percent 1.0 1.3 15)" "CPU average"
assert_equal "1.5" "$(kb_to_mb 1536)" "RSS conversion"
assert_equal "4 90 120 100 110" "$(printf '100\n120\n90\n110\n' | summarize_integer_samples)" \
  "sample summary"
assert_equal "40" "$(printf '100\n110\n120\n130\n140\n150\n' | edge_average_growth 2)" \
  "edge-average growth"
assert_equal "0" "$(printf '150\n140\n130\n120\n' | edge_average_growth 2)" \
  "negative growth clamp"

number_greater_than 2.01 2.0 || fail "greater-than comparison rejected larger value"
if number_greater_than 2.0 2.0; then fail "greater-than comparison accepted equality"; fi
if number_greater_than 1.99 2.0; then fail "greater-than comparison accepted smaller value"; fi
is_nonnegative_number 0.25 || fail "valid decimal rejected"
is_nonnegative_number 12 || fail "valid integer rejected"
if is_nonnegative_number nope; then fail "invalid number accepted"; fi
is_positive_integer 15 || fail "valid positive integer rejected"
if is_positive_integer 0; then fail "zero accepted as positive integer"; fi
is_valid_marketing_version 1.0 || fail "two-component marketing version rejected"
is_valid_marketing_version 12.34.567 || fail "three-component marketing version rejected"
if is_valid_marketing_version 1; then fail "single-component marketing version accepted"; fi
if is_valid_marketing_version 1.2.3.4; then fail "four-component marketing version accepted"; fi
if is_valid_marketing_version .1; then fail "leading-empty marketing version accepted"; fi
if is_valid_marketing_version 1.; then fail "trailing-empty marketing version accepted"; fi
if is_valid_marketing_version 1..2; then fail "empty marketing version component accepted"; fi
if is_valid_marketing_version '../1.2'; then fail "unsafe marketing version accepted"; fi
if is_valid_marketing_version '1.2 beta'; then fail "non-numeric marketing version accepted"; fi
if is_valid_marketing_version '1.\x32'; then fail "escaped marketing version accepted"; fi
is_valid_build_number 1 || fail "valid build number rejected"
is_valid_build_number 9999 || fail "four-digit build number rejected"
if is_valid_build_number 0; then fail "zero build number accepted"; fi
if is_valid_build_number 0001; then fail "leading-zero build number accepted"; fi
if is_valid_build_number 10000; then fail "oversized build number accepted"; fi
if is_valid_build_number '42;Delete :CFBundleIdentifier'; then
  fail "unsafe build number accepted"
fi
if is_valid_build_number '4\x32'; then fail "escaped build number accepted"; fi

echo "✓ verify helper tests"
