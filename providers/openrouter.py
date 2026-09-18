"""OpenRouter provider: credit balance, spend, and per-model breakdown.

Needs OPENROUTER_MANAGEMENT_KEY — a management key, not an inference key;
the credits, keys, and activity endpoints reject ordinary API keys.
"""

import os

from .common import (
    describe_error, fmt_tokens, get_json, item_row, result, summary_row,
)

ID = "openrouter"
NAME = "OpenRouter"
ENV_VARS = ("OPENROUTER_MANAGEMENT_KEY",)

BASE = "https://openrouter.ai/api/v1"
SYMBOL = "$"
MAX_KEY_PAGES = 20


def list_keys(headers: dict) -> list:
    keys = []
    for _ in range(MAX_KEY_PAGES):
        page = get_json(
            f"{BASE}/keys?include_disabled=true&offset={len(keys)}", headers,
        ).get("data", [])
        if not page:
            break
        keys.extend(page)
    return keys


def build_models(activity: list) -> list:
    models = {}
    for row in activity:
        m = models.setdefault(row.get("model", "N/A"), {
            "cost": 0.0, "prompt": 0, "completion": 0, "requests": 0,
        })
        m["cost"] += float(row.get("usage") or 0)
        m["prompt"] += int(row.get("prompt_tokens") or 0)
        m["completion"] += int(row.get("completion_tokens") or 0)
        m["requests"] += int(row.get("requests") or 0)

    ranked = sorted(models.items(), key=lambda kv: kv[1]["cost"], reverse=True)
    return [
        item_row(
            name,
            f'Input {fmt_tokens(m["prompt"])} · Output {fmt_tokens(m["completion"])}'
            f' tokens · {m["requests"]} requests',
            SYMBOL, m["cost"],
        )
        for name, m in ranked
    ]


def fetch() -> dict:
    headers = {"Authorization": f"Bearer {os.environ['OPENROUTER_MANAGEMENT_KEY']}"}

    try:
        credits = get_json(f"{BASE}/credits", headers).get("data", {})
        keys = list_keys(headers)
        activity = get_json(f"{BASE}/activity", headers).get("data", [])
    except Exception as e:
        error = describe_error(NAME, e)
        if getattr(e, "code", None) in (401, 403):
            error += " (OPENROUTER_MANAGEMENT_KEY must be a management key)"
        return result(ID, NAME, False, error=error)

    # Account-wide spend = sum over every key's own counters; the credits
    # endpoint only gives the lifetime total.
    def total(field: str) -> float:
        return sum(float(k.get(field) or 0) for k in keys)

    balance = float(credits.get("total_credits") or 0) - float(credits.get("total_usage") or 0)

    summary = [
        summary_row("Credit balance", SYMBOL, balance, primary=True),
        summary_row("Today", SYMBOL, total("usage_daily")),
        summary_row("This week", SYMBOL, total("usage_weekly")),
        summary_row("This month", SYMBOL, total("usage_monthly")),
    ]

    return result(ID, NAME, True, summary=summary, sections=[
        {"title": "By model (last 30 days)", "rows": build_models(activity)},
    ])
