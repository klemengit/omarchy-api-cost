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
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ORG_ID = os.environ.get("SCW_ORG_ID", "e6cac714-33c8-4f79-9475-4598d38670fe")
CURRENCY_SYMBOLS = {"EUR": "€", "USD": "$", "GBP": "£"}


def money(value: dict) -> float:
    return value.get("units", 0) + value.get("nanos", 0) / 1_000_000_000


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

    resources = sorted(
        (
            {
                "name": item.get("resource_name", "N/A"),
                "category": item.get("category_name", "N/A"),
                "qty": item.get("billed_quantity", "N/A"),
                "unit": item.get("unit", "N/A"),
                "cost": round(money(item.get("value", {})), 2),
            }
            for item in consumptions
        ),
        key=lambda r: r["cost"],
        reverse=True,
    )

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
