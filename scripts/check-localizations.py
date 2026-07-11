#!/usr/bin/env python3
"""Check explicit Swift localization keys against Localizable.xcstrings.

The app deliberately routes user-facing copy through typed LocalizedStringKey accessors or the
Foundation-side `t`/`String(localized:)` helpers. Restricting extraction to those explicit forms
keeps this check deterministic; it does not try to infer whether arbitrary Swift string literals
are user-facing.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = ROOT / "Resources" / "Localizable.xcstrings"
SOURCE_ROOT = ROOT / "Sources"

SWIFT_STRING = r'"((?:\\.|[^"\\])*)"'
KEY_PATTERNS = (
    re.compile(r"\bLocalizedStringKey\s*=\s*" + SWIFT_STRING),
    re.compile(r"\bLocalizedStringResource\s*\(\s*" + SWIFT_STRING),
    re.compile(r"\bString\s*\(\s*localized:\s*" + SWIFT_STRING),
    re.compile(r"\bt\s*\(\s*" + SWIFT_STRING + r"\s*,"),
)


class CheckFailure(Exception):
    pass


def without_swift_comments(source: str) -> str:
    """Replace comments with spaces while retaining offsets/newlines and string literals.

    Swift permits nested block comments. Handling strings before comment delimiters also prevents
    URLs and comment-looking release copy inside literals from confusing extraction.
    """

    result = list(source)
    index = 0
    length = len(source)

    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index)
            if end == -1:
                end = length
            for position in range(index, end):
                result[position] = " "
            index = end
            continue

        if source.startswith("/*", index):
            depth = 1
            position = index + 2
            while position < length and depth:
                if source.startswith("/*", position):
                    depth += 1
                    position += 2
                    continue
                if source.startswith("*/", position):
                    depth -= 1
                    position += 2
                    continue
                position += 1
            for comment_index in range(index, position):
                if result[comment_index] != "\n":
                    result[comment_index] = " "
            index = position
            continue

        if source[index] == '"':
            triple = source.startswith('"""', index)
            delimiter = '"""' if triple else '"'
            position = index + len(delimiter)
            while position < length:
                if source.startswith(delimiter, position):
                    position += len(delimiter)
                    break
                if not triple and source[position] == "\\":
                    position += 2
                else:
                    position += 1
            index = position
            continue

        index += 1

    return "".join(result)


def decode_swift_key(raw: str, path: Path, line: int) -> str:
    # Localization keys use ordinary Swift literals whose escape grammar is JSON-compatible.
    try:
        value = json.loads(f'"{raw}"')
    except json.JSONDecodeError as error:
        raise CheckFailure(
            f"{path.relative_to(ROOT)}:{line}: unsupported localization-key escape: {error}"
        ) from error
    if not value:
        raise CheckFailure(f"{path.relative_to(ROOT)}:{line}: localization key is empty")
    return value


def source_references() -> dict[str, list[str]]:
    references: dict[str, list[str]] = {}
    swift_files = sorted(SOURCE_ROOT.rglob("*.swift"))
    if not swift_files:
        raise CheckFailure(f"no Swift sources found beneath {SOURCE_ROOT.relative_to(ROOT)}")

    for path in swift_files:
        source = without_swift_comments(path.read_text(encoding="utf-8"))
        for pattern in KEY_PATTERNS:
            for match in pattern.finditer(source):
                line = source.count("\n", 0, match.start()) + 1
                key = decode_swift_key(match.group(1), path, line)
                references.setdefault(key, []).append(f"{path.relative_to(ROOT)}:{line}")
    return references


def catalog_keys() -> set[str]:
    try:
        document = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CheckFailure(f"catalog is missing: {CATALOG_PATH.relative_to(ROOT)}") from error
    except json.JSONDecodeError as error:
        raise CheckFailure(f"catalog is not valid JSON: {error}") from error

    source_language = document.get("sourceLanguage")
    strings = document.get("strings")
    if not isinstance(source_language, str) or not source_language:
        raise CheckFailure("catalog sourceLanguage must be a nonempty string")
    if not isinstance(strings, dict) or not strings:
        raise CheckFailure("catalog strings must be a nonempty object")

    for key, entry in strings.items():
        if not isinstance(key, str) or not key:
            raise CheckFailure("catalog contains an empty or non-string key")
        if not isinstance(entry, dict):
            raise CheckFailure(f"catalog entry {key!r} must be an object")
        localization = entry.get("localizations", {}).get(source_language)
        if not isinstance(localization, dict):
            raise CheckFailure(f"catalog entry {key!r} has no {source_language!r} localization")
        units = collect_string_units(localization)
        if not units:
            raise CheckFailure(f"catalog entry {key!r} has no source-language string unit")
        if any(not isinstance(unit.get("value"), str) or not unit["value"] for unit in units):
            raise CheckFailure(f"catalog entry {key!r} has an empty source-language value")

    return set(strings)


def collect_string_units(node: object) -> list[dict[str, object]]:
    if isinstance(node, dict):
        units: list[dict[str, object]] = []
        unit = node.get("stringUnit")
        if isinstance(unit, dict):
            units.append(unit)
        for key, value in node.items():
            if key != "stringUnit":
                units.extend(collect_string_units(value))
        return units
    if isinstance(node, list):
        units = []
        for value in node:
            units.extend(collect_string_units(value))
        return units
    return []


def main() -> int:
    try:
        references = source_references()
        catalog = catalog_keys()
    except (CheckFailure, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    referenced = set(references)
    missing = sorted(referenced - catalog)
    orphaned = sorted(catalog - referenced)
    if missing:
        print("error: localization keys referenced by Swift are absent from the catalog:", file=sys.stderr)
        for key in missing:
            print(f"  {key}: {', '.join(references[key])}", file=sys.stderr)
    if orphaned:
        print("error: localization catalog keys have no explicit Swift accessor/use:", file=sys.stderr)
        for key in orphaned:
            print(f"  {key}", file=sys.stderr)
    if missing or orphaned:
        return 1

    print(f"✓ localization catalog matches {len(catalog)} explicit Swift keys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
