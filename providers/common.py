"""Shared helpers for provider fetchers.

Every provider's ``fetch()`` returns one dict in the same shape, so the
widget renders every tab with the same QML:

    {
      "id", "name", "ok", "error", "updated",
      "summary":  [{"label", "value", "primary", "negative"}],
      "sections": [{"title", "rows": [{"name", "detail", "amount", "negative"}]}],
    }

Amounts are pre-formatted strings; the widget does no number formatting.
"""

import json
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

CURRENCY_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fmt_money(symbol: str, value: float) -> str:
    text = f"{symbol}{abs(value):.2f}"
    return "-" + text if value < -0.005 else text


def fmt_tokens(tokens: float) -> str:
    if tokens >= 1_000_000:
        return f"{tokens / 1_000_000:.2f}M"
    if tokens >= 1_000:
        return f"{tokens / 1_000:.0f}K"
    return f"{tokens:.0f}"


def summary_row(label: str, symbol: str, value: float, primary: bool = False) -> dict:
    return {
        "label": label,
        "value": fmt_money(symbol, value),
        "primary": primary,
        "negative": value < -0.005,
    }


def item_row(name: str, detail: str, symbol: str, value: float) -> dict:
    return {
        "name": name,
        "detail": detail,
        "amount": fmt_money(symbol, value),
        "negative": value < -0.005,
    }


def result(pid: str, name: str, ok: bool, error: str = None,
           summary: list = None, sections: list = None) -> dict:
    return {
        "id": pid,
        "name": name,
        "ok": ok,
        "error": error,
        "updated": now_iso(),
        "summary": summary or [],
        "sections": [s for s in (sections or []) if s["rows"]],
    }


def get_json(url: str, headers: dict) -> dict:
    with urlopen(Request(url, headers=headers), timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def describe_error(label: str, exc: Exception) -> str:
    if isinstance(exc, HTTPError):
        return f"{label} API error: HTTP {exc.code}"
    if isinstance(exc, URLError):
        return f"{label} API unreachable: {exc.reason}"
    return f"{label}: {exc}"
