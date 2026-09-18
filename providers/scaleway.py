"""Scaleway provider: current-month billing from the billing v2beta1 API.

Needs SCW_API_KEY (secret key with billing read access) and SCW_ORG_ID.
"""

import os
import re

from .common import (
    CURRENCY_SYMBOLS, describe_error, fmt_tokens, get_json, item_row, result,
    summary_row,
)

ID = "scaleway"
NAME = "Scaleway"
ENV_VARS = ("SCW_API_KEY", "SCW_ORG_ID")

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


def build_resources(consumptions: list, symbol: str) -> list:
    plain = []
    grouped = {}
    for item in consumptions:
        name = item.get("resource_name", "N/A")
        category = item.get("category_name", "N/A")
        cost = money(item.get("value", {}))
        parsed = split_model_resource(name) if item.get("unit") == "token" else None
        if parsed is None:
            detail = f'{category} · {item.get("billed_quantity", "N/A")} {item.get("unit", "N/A")}'
            plain.append((cost, item_row(name, detail, symbol, cost)))
            continue

        model, region, direction = parsed
        group = grouped.setdefault((model, region), {
            "name": f"{model} ({region})",
            "category": category,
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

    # Scaleway reports Generative-APIs billed_quantity in thousands of tokens.
    merged = [
        (g["cost"], item_row(
            g["name"],
            f'{g["category"]} · Input {fmt_tokens(g["inputK"] * 1000)}'
            f' · Output {fmt_tokens(g["outputK"] * 1000)} tokens',
            symbol, g["cost"],
        ))
        for g in grouped.values()
    ]

    return [row for _, row in sorted(plain + merged, key=lambda r: r[0], reverse=True)]


def fmt_date(d: str) -> str:
    return d.split("T")[0] if d and d != "N/A" else "N/A"


def fetch() -> dict:
    api_key = os.environ["SCW_API_KEY"]
    org_id = os.environ["SCW_ORG_ID"]
    headers = {"X-Auth-Token": api_key}

    try:
        consumptions = get_json(
            f"https://api.scaleway.com/billing/v2beta1/consumptions?organization_id={org_id}",
            headers,
        ).get("consumptions", [])
        invoices = get_json(
            "https://api.scaleway.com/billing/v2beta1/invoices", headers,
        ).get("invoices", [])
    except Exception as e:
        return result(ID, NAME, False, error=describe_error(NAME, e))

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

    summary = [
        summary_row("Net spend this month", symbol, net_total, primary=True),
        summary_row("Before credits", symbol, before_credits),
    ]
    if credit != 0:
        summary.append(summary_row("Free tier credit", symbol, credit))

    invoice_rows = [
        item_row(
            f'{fmt_date(inv.get("start_date"))} to {fmt_date(inv.get("stop_date"))}',
            f'Invoice {inv.get("number", "N/A")} · {inv.get("state", "N/A")}',
            symbol, money(inv.get("total_taxed", {})),
        )
        for inv in invoices[:3]
    ]

    return result(ID, NAME, True, summary=summary, sections=[
        {"title": "Breakdown by resource", "rows": build_resources(consumptions, symbol)},
        {"title": "Recent invoices", "rows": invoice_rows},
    ])
