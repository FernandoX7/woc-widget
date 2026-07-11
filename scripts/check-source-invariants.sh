#!/bin/bash
# Deterministic architecture checks that do not require compiling the app.
# Keep this compatible with the stock macOS /bin/bash 3.2.
set -euo pipefail
cd "$(dirname "$0")/.."

WOCKIT_ROOT="Sources/WoCKit"

[[ -d "$WOCKIT_ROOT" ]] || {
  echo "error: WoCKit source directory is missing: $WOCKIT_ROOT" >&2
  exit 1
}

if ! find "$WOCKIT_ROOT" -type f -name '*.swift' -print -quit | grep -q .; then
  echo "error: WoCKit contains no Swift sources" >&2
  exit 1
fi

# WoCKit is the package-built, headlessly testable domain layer. Qualified/selective imports and
# common import attributes are covered as well as plain `import Framework` declarations.
FORBIDDEN_IMPORTS="$({
  find "$WOCKIT_ROOT" -type f -name '*.swift' -exec grep -HnE \
    '^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*import([[:space:]]+(class|enum|func|protocol|struct|typealias|var))?[[:space:]]+(SwiftUI|AppKit|Charts)([[:space:].]|$)' \
    {} + || true
})"

if [[ -n "$FORBIDDEN_IMPORTS" ]]; then
  echo "error: Sources/WoCKit must remain free of SwiftUI, AppKit, and Charts imports:" >&2
  echo "$FORBIDDEN_IMPORTS" >&2
  exit 1
fi

echo "✓ WoCKit import boundary (Foundation/domain only)"
