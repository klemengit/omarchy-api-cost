# API Cost

An [Omarchy](https://omarchy.org/) bar plugin that shows your cloud and AI API spend. The bar shows a small icon; click it to open a cost dashboard with one tab per configured provider — no separate TUI or terminal needed.

Providers:

- **Scaleway** — net spend this month, spend before credits, free-tier credit applied, every billed line item this month, and the last three invoices.
- **OpenRouter** — credit balance, spend today / this week / this month, and a per-model breakdown (cost, tokens, requests) for the last 30 days.

Only providers whose credentials are set get a tab; with a single provider the tab row is hidden.

Keys in the popup: `r` refreshes, `Tab` / `h` / `l` switch tabs, `1`–`9` jump to a tab, `Esc` closes.

The popup paints the last numbers immediately and only refetches if they are older than five minutes; `r` and the refresh button always refetch. The payload and the selected tab are cached in `~/.local/state/omarchy/api-cost/state.json`, so the tab you were on survives a shell restart. Set `"maxAgeSeconds"` on the widget's `bar.layout` entry in `shell.json` to change the five minutes.

## Requirements

- [Omarchy](https://omarchy.org/) with the Quickshell-based bar.
- Python 3 on `PATH`.
- Credentials for at least one provider (below).

## Setup

1. Install the plugin:
   ```bash
   omarchy plugin add https://github.com/klemengit/omarchy-api-cost.git --enable
   ```
   Or clone it manually into `~/.config/omarchy/plugins/io.github.klemengit.api-cost` and add it to the bar in `~/.config/omarchy/shell.json`, e.g. under `bar.layout.right`:
   ```json
   { "id": "io.github.klemengit.api-cost" }
   ```
2. Get credentials for the providers you use:
   - **Scaleway** ([console](https://console.scaleway.com/)):
     - `SCW_API_KEY` — create an API key under **IAM → API Keys**, scoped to (or belonging to a member with) read access to billing. Use the key's **Secret Key**, not the Access Key.
     - `SCW_ORG_ID` — your **Organization ID**, shown under **Organization → Settings** (or in Account settings).
   - **OpenRouter** ([management keys docs](https://openrouter.ai/docs/guides/overview/auth/management-api-keys)):
     - `OPENROUTER_MANAGEMENT_KEY` — a **management key**, created in the OpenRouter account settings. An ordinary inference API key is rejected by the credit and activity endpoints.
3. Export them in the session environment — e.g. via Hyprland's `envs.local.lua`:
   ```lua
   hl.env("SCW_API_KEY", "<secret key>")
   hl.env("SCW_ORG_ID", "<organization id>")
   hl.env("OPENROUTER_MANAGEMENT_KEY", "<management key>")
   ```
   or your shell profile.

To open the popup from a keybinding: `omarchy-shell shell toggle io.github.klemengit.api-cost`.

## How it works

`api-cost.py` runs every provider whose environment variables are set (in parallel) and prints a single JSON line. Each provider module in `providers/` returns the same shape — a summary list and titled sections of rows, with amounts pre-formatted — so `BarWidget.qml` renders every tab with the same code. Nothing raises: a failing provider reports `"ok": false` with an error message in its own tab, and the other tabs are unaffected.

`BarWidget.qml` caches each payload to `~/.local/state/omarchy/api-cost/state.json` and hydrates from it at startup, so opening the popup never shows an empty panel while a fetch is in flight.

To add a provider, write `providers/<name>.py` with `ID`, `NAME`, `ENV_VARS`, and a `fetch()` returning `common.result(...)`, then add it to `PROVIDERS` in `providers/__init__.py`.
