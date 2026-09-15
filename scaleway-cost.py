#!/usr/bin/env python3
"""Fetch Scaleway cost-dashboard data and print it as one JSON line.

Consumed by the io.github.klemengit.scaleway-cost bar-widget plugin
(BarWidget.qml), whose popup *is* the dashboard (summary, per-resource
breakdown, recent invoices) — no separate TUI/terminal needed. Never
raises: any failure still prints valid JSON with "ok": false so the widget
can show an error state instead of crashing.
"""

import json
import os
import re
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ORG_ID = os.environ.get("SCW_ORG_ID", "e6cac714-33c8-4f79-9475-4598d38670fe")
CURRENCY_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}

# Generative-APIs line items look like "GLM 5.2 - Input - FR-PAR" or
# "DeepSeek V4 Flash - Input - Cached - fr-par". Split off the model and
# region so input/output rows for the same model can be merged onto one line.
MODEL_DIRECTION_RE = re.compile(
    r"^(.*?)\s*-\s*(Input|Output)(?:\s*-\s*Cached)?\s*-\s*([A-Za-z]{2}-[A-Za-z]{3,4})$",
    re.IGNORECASE,
)


def money(value: dict) -> float:
    return value.get("units", 0) + value.get("nanos", 0) / 1_000_000_000


def split_model_resource(name: str):
    m = MODEL_DIRECTION_RE.match(name)
    if not m:
        return None
    model, direction, region = m.groups()
    return model.strip(), region.upper(), direction.lower()


def fmt_token_qty(k_tokens: float) -> str:
    # Scaleway reports Generative-APIs billed_quantity in thousands of tokens.
    if k_tokens >= 1000:
        return f"{k_tokens / 1000:.2f}M"
    return f"{k_tokens:.0f}K"


def build_resources(consumptions: list) -> list:
    plain = []
    grouped = {}
    for item in consumptions:
        name = item.get("resource_name", "N/A")
        cost = money(item.get("value", {}))
        parsed = split_model_resource(name) if item.get("unit") == "token" else None
        if parsed is None:
            plain.append({
                "name": name,
                "category": item.get("category_name", "N/A"),
                "qty": item.get("billed_quantity", "N/A"),
                "unit": item.get("unit", "N/A"),
                "cost": round(cost, 2),
            })
            continue

        model, region, direction = parsed
        group = grouped.setdefault((model, region), {
            "name": f"{model} ({region})",
            "category": item.get("category_name", "N/A"),
            "cost": 0.0,
            "inputK": 0.0,
            "outputK": 0.0,
        })
        group["cost"] += cost
        try:
            qty = float(item.get("billed_quantity", 0) or 0)
        except (TypeError, ValueError):
            qty = 0.0
        group["inputK" if direction == "input" else "outputK"] += qty

    merged = [
        {
            "name": g["name"],
            "category": g["category"],
            "cost": round(g["cost"], 2),
            "unit": "token",
            "tokenSummary": f"Input {fmt_token_qty(g['inputK'])} · Output {fmt_token_qty(g['outputK'])} tokens",
        }
        for g in grouped.values()
    ]

    return sorted(plain + merged, key=lambda r: r["cost"], reverse=True)


def emit(ok: bool, **fields) -> None:
    payload = {
        "ok": ok,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "error": None,
        "currency": "EUR",
        "symbol": "€",
        "net": None,
        "beforeCredits": None,
        "credit": None,
        "resources": [],
        "invoices": [],
    }
    payload.update(fields)
    print(json.dumps(payload))


def get_json(url: str, api_key: str) -> dict:
    req = Request(url, headers={"X-Auth-Token": api_key})
    with urlopen(req, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def fmt_date(d: str) -> str:
    return d.split("T")[0] if d and d != "N/A" else "N/A"


def main() -> None:
    api_key = os.environ.get("SCW_API_KEY")
    if not api_key:
        emit(False, error="SCW_API_KEY not set in the session environment")
        return

    try:
        consumptions = get_json(
            f"https://api.scaleway.com/billing/v2beta1/consumptions?organization_id={ORG_ID}",
            api_key,
        ).get("consumptions", [])
        invoices = get_json(
            "https://api.scaleway.com/billing/v2beta1/invoices",
            api_key,
        ).get("invoices", [])
    except HTTPError as e:
        emit(False, error=f"Scaleway API error: HTTP {e.code}")
        return
    except URLError as e:
        emit(False, error=f"Scaleway API unreachable: {e.reason}")
        return
    except Exception as e:
        emit(False, error=str(e))
        return

    currency = consumptions[0]["value"].get("currency_code", "EUR") if consumptions else "EUR"
    symbol = CURRENCY_SYMBOLS.get(currency, currency + " ")

    net_total = 0.0
    before_credits = 0.0
    credit = 0.0
    for item in consumptions:
        cost = money(item.get("value", {}))
        net_total += cost
        if cost >= 0:
            before_credits += cost
        else:
            credit += cost
    if abs(net_total) < 0.005:
        net_total = 0.0

    resources = build_resources(consumptions)

    invoice_rows = [
        {
            "number": inv.get("number", "N/A"),
            "period": f'{fmt_date(inv.get("start_date"))} to {fmt_date(inv.get("stop_date"))}',
            "total": round(money(inv.get("total_taxed", {})), 2),
            "state": inv.get("state", "N/A"),
        }
        for inv in invoices[:3]
    ]

    emit(
        True,
        net=round(net_total, 2),
        beforeCredits=round(before_credits, 2),
        credit=round(credit, 2),
        currency=currency,
        symbol=symbol,
        resources=resources,
        invoices=invoice_rows,
    )


if __name__ == "__main__":
    main()
