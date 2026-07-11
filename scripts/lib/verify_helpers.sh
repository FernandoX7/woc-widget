#!/bin/bash
# Pure helpers shared by the verification/release scripts and shell tests. Keep this compatible
# with the stock macOS /bin/bash 3.2.

cpu_time_to_seconds() {
  local value="${1:-}"
  awk -v value="$value" '
    BEGIN {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "") exit 2
      days = 0
      if (index(value, "-") > 0) {
        dayCount = split(value, dayParts, "-")
        if (dayCount != 2 || dayParts[1] !~ /^[0-9]+$/) exit 2
        days = dayParts[1] + 0
        value = dayParts[2]
      }
      count = split(value, parts, ":")
      if (count == 3) {
        if (parts[1] !~ /^[0-9]+$/ || parts[2] !~ /^[0-9]+$/ ||
            parts[3] !~ /^[0-9]+([.][0-9]+)?$/) exit 2
        hours = parts[1] + 0; minutes = parts[2] + 0; seconds = parts[3] + 0
      } else if (count == 2) {
        if (parts[1] !~ /^[0-9]+$/ || parts[2] !~ /^[0-9]+([.][0-9]+)?$/) exit 2
        hours = 0; minutes = parts[1] + 0; seconds = parts[2] + 0
      } else if (count == 1) {
        if (parts[1] !~ /^[0-9]+([.][0-9]+)?$/) exit 2
        hours = 0; minutes = 0; seconds = parts[1] + 0
      } else {
        exit 2
      }
      if (minutes >= 60 || seconds >= 60) exit 2
      printf "%.3f\n", days * 86400 + hours * 3600 + minutes * 60 + seconds
    }
  '
}

cpu_average_percent() {
  local start_seconds="$1"
  local end_seconds="$2"
  local elapsed_seconds="$3"
  awk -v start="$start_seconds" -v end="$end_seconds" -v elapsed="$elapsed_seconds" '
    BEGIN {
      if (elapsed <= 0 || end < start) exit 2
      printf "%.2f\n", ((end - start) / elapsed) * 100
    }
  '
}

number_greater_than() {
  local lhs="$1"
  local rhs="$2"
  awk -v lhs="$lhs" -v rhs="$rhs" 'BEGIN { exit !((lhs + 0) > (rhs + 0)) }'
}

is_nonnegative_number() {
  local value="${1:-}"
  awk -v value="$value" 'BEGIN {
    exit !(value ~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)$/)
  }'
}

is_positive_integer() {
  local value="${1:-}"
  awk -v value="$value" 'BEGIN { exit !(value ~ /^[1-9][0-9]*$/) }'
}

# Safe subset of CFBundleShortVersionString used by the release artifact name and PlistBuddy.
# The checked-in value is currently two-component (1.0), so accept two or three numeric components.
is_valid_marketing_version() {
  local value="${1:-}"
  case "$value" in
    ""|*[!0-9.]*) return 1 ;;
  esac
  awk -v value="$value" 'BEGIN {
    if (length(value) > 32) exit 1
    count = split(value, parts, ".")
    if (count < 2 || count > 3) exit 1
    for (part_index = 1; part_index <= count; part_index += 1) {
      if (parts[part_index] !~ /^[0-9]+$/) exit 1
    }
    exit 0
  }'
}

# Keep release build numbers in Apple's documented first-component range and reject values that
# could be interpreted as PlistBuddy commands or filesystem path fragments.
is_valid_build_number() {
  local value="${1:-}"
  case "$value" in
    ""|*[!0-9]*) return 1 ;;
  esac
  awk -v value="$value" 'BEGIN {
    exit !(length(value) <= 4 && value ~ /^[1-9][0-9]*$/)
  }'
}

kb_to_mb() {
  local kilobytes="$1"
  awk -v kb="$kilobytes" 'BEGIN { printf "%.1f\n", kb / 1024 }'
}

# Reads one non-negative integer per line and emits:
#   <count> <minimum> <maximum> <first> <last>
summarize_integer_samples() {
  awk '
    /^[[:space:]]*$/ { next }
    $1 !~ /^[0-9]+$/ { exit 2 }
    {
      value = $1 + 0
      if (count == 0) { minimum = value; maximum = value; first = value }
      if (value < minimum) minimum = value
      if (value > maximum) maximum = value
      last = value
      count += 1
    }
    END {
      if (count == 0) exit 3
      printf "%d %d %d %d %d\n", count, minimum, maximum, first, last
    }
  '
}

# Net growth between the average of the first and last `window` samples. Averaging avoids a single
# allocator/cache fluctuation at either edge turning into a false regression.
edge_average_growth() {
  local window="${1:-3}"
  awk -v window="$window" '
    /^[[:space:]]*$/ { next }
    $1 !~ /^[0-9]+$/ { exit 2 }
    { values[++count] = $1 + 0 }
    END {
      if (count == 0 || window !~ /^[1-9][0-9]*$/) exit 3
      if (window > count) window = count
      first = 0; last = 0
      for (i = 1; i <= window; i++) {
        first += values[i]
        last += values[count - window + i]
      }
      growth = (last / window) - (first / window)
      if (growth < 0) growth = 0
      printf "%.0f\n", growth
    }
  '
}
