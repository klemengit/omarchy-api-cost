#!/usr/bin/env python3
"""Fetch cost data from every configured provider and print one JSON line.

Consumed by the io.github.klemengit.api-cost bar-widget plugin
(BarWidget.qml), which shows one popup tab per provider. A provider is
enabled when all of its environment variables are set. Never raises: a
failing provider reports "ok": false in its own entry, and the other
providers are unaffected.
"""

import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from providers import PROVIDERS  # noqa: E402
from providers.common import describe_error, result  # noqa: E402


def run(provider) -> dict:
    try:
        return provider.fetch()
    except Exception as e:
        return result(provider.ID, provider.NAME, False, error=describe_error(provider.NAME, e))


def main() -> None:
    enabled = [p for p in PROVIDERS if all(os.environ.get(v) for v in p.ENV_VARS)]
    error = None
    if not enabled:
        needed = " or ".join(" + ".join(p.ENV_VARS) for p in PROVIDERS)
        error = f"No provider configured — set {needed} in the session environment"

    with ThreadPoolExecutor(max_workers=max(1, len(enabled))) as pool:
        providers = list(pool.map(run, enabled))

    print(json.dumps({"providers": providers, "error": error}))


if __name__ == "__main__":
    main()
