#!/usr/bin/env python3
"""Credential-free contract smoke test for the app's live public JSON feeds.

This intentionally belongs in a scheduled/manual workflow, not pull-request verification. It
checks stable response shapes and configured market identity while allowing every volatile value
(player counts, prices, release contents, and leaderboard membership) to change freely.
"""

from __future__ import annotations

import json
import math
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Callable, Optional


TIMEOUT_SECONDS = 12
MAXIMUM_RESPONSE_BYTES = 2 * 1024 * 1024
USER_AGENT = "woc-widget-live-contract-smoke/1.0"
PAIR_ADDRESS = "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p"
TOKEN_ADDRESS = "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"


class ContractError(Exception):
    pass


@dataclass(frozen=True)
class Endpoint:
    name: str
    url: str
    validate: Callable[[object], None]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def is_nonnegative_int(value: object) -> bool:
    return is_int(value) and value >= 0


def is_finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def finite_decimal(value: object) -> Optional[float]:
    if not isinstance(value, (str, int, float)) or isinstance(value, bool):
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) else None


def object_root(payload: object, endpoint: str) -> dict[str, object]:
    require(isinstance(payload, dict), f"{endpoint}: root must be an object")
    return payload


def validate_status(payload: object) -> None:
    root = object_root(payload, "status")
    require(is_nonnegative_int(root.get("players_online")),
            "status: players_online must be a nonnegative integer")
    if "ok" in root:
        require(isinstance(root["ok"], bool), "status: ok must be a boolean when present")
    if "realm" in root:
        require(root["realm"] is None or isinstance(root["realm"], str),
                "status: realm must be a string or null when present")
    if "names" in root:
        require(isinstance(root["names"], list) and
                all(isinstance(name, str) for name in root["names"]),
                "status: names must be an array of strings when present")


def validate_project_stats(payload: object) -> None:
    root = object_root(payload, "project-stats")
    usable = False
    for key in ("accounts_created", "players_online"):
        if key in root:
            require(is_nonnegative_int(root[key]), f"project-stats: {key} must be nonnegative")
            usable = True
    if "realm" in root:
        require(isinstance(root["realm"], str), "project-stats: realm must be a string")
        usable = usable or bool(root["realm"].strip())
    require(usable, "project-stats: response contains no usable typed field")


def validate_releases(payload: object) -> None:
    root = object_root(payload, "releases")
    releases = root.get("releases")
    require(isinstance(releases, list), "releases: releases must be an array")
    for index, release in enumerate(releases):
        require(isinstance(release, dict), f"releases: item {index} must be an object")
        identity = (
            is_nonnegative_int(release.get("id"))
            or any(isinstance(release.get(key), str) and release[key].strip()
                   for key in ("tag", "name"))
            or isinstance(release.get("url"), str) and release["url"].startswith("https://")
        )
        require(bool(identity), f"releases: item {index} has no usable identity")
        if "prerelease" in release:
            require(isinstance(release["prerelease"], bool),
                    f"releases: item {index} prerelease must be boolean")


def validate_leaderboard(payload: object) -> None:
    root = object_root(payload, "leaderboard")
    leaders = root.get("leaders")
    require(isinstance(leaders, list), "leaderboard: leaders must be an array")
    for index, leader in enumerate(leaders):
        require(isinstance(leader, dict), f"leaderboard: item {index} must be an object")
        require(isinstance(leader.get("name"), str) and bool(leader["name"].strip()),
                f"leaderboard: item {index} must have a nonempty name")
    for key in ("page", "pageCount", "total", "pageSize"):
        if key in root:
            require(is_nonnegative_int(root[key]), f"leaderboard: {key} must be nonnegative")


def validate_realms(payload: object) -> None:
    root = object_root(payload, "realms")
    realms = root.get("realms")
    characters = root.get("characters")
    require(isinstance(realms, list), "realms: realms must be an array")
    require(isinstance(characters, dict), "realms: characters must be an object")
    for index, realm in enumerate(realms):
        require(isinstance(realm, dict), f"realms: item {index} must be an object")
        require(isinstance(realm.get("name"), str) and bool(realm["name"].strip()),
                f"realms: item {index} must have a nonempty name")
    require(all(isinstance(name, str) and name and is_nonnegative_int(count)
                for name, count in characters.items()),
            "realms: character counts must map nonempty realm names to nonnegative integers")


def validate_dexscreener(payload: object) -> None:
    root = object_root(payload, "DexScreener")
    pairs = root.get("pairs")
    require(isinstance(pairs, list), "DexScreener: documented pairs field must be an array")
    expected = None
    for pair in pairs:
        if not isinstance(pair, dict):
            continue
        tokens = (pair.get("baseToken"), pair.get("quoteToken"))
        addresses = {token.get("address") for token in tokens if isinstance(token, dict)}
        if (str(pair.get("chainId", "")).lower() == "solana"
                and pair.get("pairAddress") == PAIR_ADDRESS
                and TOKEN_ADDRESS in addresses):
            expected = pair
            break
    require(expected is not None, "DexScreener: configured Solana WOC pair is absent")
    require((finite_decimal(expected.get("priceUsd")) or 0) > 0,
            "DexScreener: priceUsd must be a positive finite decimal")
    changes = expected.get("priceChange")
    require(isinstance(changes, dict) and finite_decimal(changes.get("h24")) is not None,
            "DexScreener: priceChange.h24 must be a finite number")


def validate_geckoterminal(payload: object) -> None:
    root = object_root(payload, "GeckoTerminal")
    data = root.get("data")
    attributes = data.get("attributes") if isinstance(data, dict) else None
    rows = attributes.get("ohlcv_list") if isinstance(attributes, dict) else None
    require(isinstance(rows, list), "GeckoTerminal: data.attributes.ohlcv_list must be an array")
    for index, row in enumerate(rows):
        require(isinstance(row, list) and len(row) >= 5,
                f"GeckoTerminal: OHLCV row {index} must have at least five values")
        require(all(is_finite_number(value) for value in row[:6]),
                f"GeckoTerminal: OHLCV row {index} contains a non-finite/non-numeric value")
        timestamp, open_price, high, low, close = row[:5]
        require(timestamp > 0 and min(open_price, high, low, close) > 0,
                f"GeckoTerminal: OHLCV row {index} contains a non-positive timestamp/price")
        require(low <= min(open_price, close) and high >= max(open_price, close),
                f"GeckoTerminal: OHLCV row {index} has an impossible high/low range")


ENDPOINTS = (
    Endpoint("realm status", "https://worldofclaudecraft.com/api/status", validate_status),
    Endpoint("project stats", "https://worldofclaudecraft.com/api/project-stats",
             validate_project_stats),
    Endpoint("releases", "https://worldofclaudecraft.com/api/releases?limit=2", validate_releases),
    Endpoint("leaderboard", "https://worldofclaudecraft.com/api/leaderboard?limit=2",
             validate_leaderboard),
    Endpoint("realms", "https://worldofclaudecraft.com/api/realms", validate_realms),
    Endpoint(
        "DexScreener spot",
        "https://api.dexscreener.com/latest/dex/pairs/solana/"
        "5we9yjzpeqxcyl4jn9khjtsr48xzyh47xtar9kg3wy1p",
        validate_dexscreener,
    ),
    Endpoint(
        "GeckoTerminal candles",
        "https://api.geckoterminal.com/api/v2/networks/solana/pools/"
        f"{PAIR_ADDRESS}/ohlcv/minute?aggregate=5&limit=2&currency=usd",
        validate_geckoterminal,
    ),
)


def fetch(endpoint: Endpoint) -> None:
    request = urllib.request.Request(
        endpoint.url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    last_error: Optional[Exception] = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                declared_length = response.headers.get("Content-Length")
                if declared_length and int(declared_length) > MAXIMUM_RESPONSE_BYTES:
                    raise ContractError(
                        f"response exceeds {MAXIMUM_RESPONSE_BYTES} bytes ({declared_length})"
                    )
                body = response.read(MAXIMUM_RESPONSE_BYTES + 1)
                require(len(body) <= MAXIMUM_RESPONSE_BYTES,
                        f"response exceeds {MAXIMUM_RESPONSE_BYTES} bytes")
            payload = json.loads(body)
            endpoint.validate(payload)
            return
        except (ContractError, json.JSONDecodeError) as error:
            # A successful response with a broken contract will not improve on an immediate retry.
            raise ContractError(str(error)) from error
        except (OSError, urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
            last_error = error
            if attempt < 2:
                time.sleep(2 ** attempt)
    raise ContractError(f"request failed after 3 attempts: {last_error}")


def main() -> int:
    failures: dict[str, str] = {}
    successes: set[str] = set()
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(fetch, endpoint): endpoint for endpoint in ENDPOINTS}
        for future in as_completed(futures):
            endpoint = futures[future]
            try:
                future.result()
                successes.add(endpoint.name)
            except Exception as error:  # Aggregate all independent feed failures in one run.
                failures[endpoint.name] = str(error)

    for endpoint in ENDPOINTS:
        if endpoint.name in successes:
            print(f"✓ {endpoint.name}")
        else:
            print(f"✗ {endpoint.name}: {failures[endpoint.name]}", file=sys.stderr)
    if failures:
        print(f"error: {len(failures)} live API contract(s) failed", file=sys.stderr)
        return 1
    print(f"✓ all {len(ENDPOINTS)} live public API contracts are compatible")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
