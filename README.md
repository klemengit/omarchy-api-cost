# Scaleway Cost

An [Omarchy](https://omarchy.org/) bar plugin that shows your current-month Scaleway net spend. Click the pill to open a popup with a full cost dashboard — no separate TUI or terminal needed.

The popup shows:

- **Summary** — total net spend, spend before credits, and free-tier credit applied.
- **Breakdown by resource** — every billed line item this month, sorted by cost, with category and quantity.
- **Recent invoices** — the last three invoices with period, total, and state.

Right-click the pill (or use the refresh button in the popup) to force an immediate refresh; otherwise it polls on a timer.

## Requirements

- [Omarchy](https://omarchy.org/) with the Quickshell-based bar.
- Python 3 on `PATH`.
- A Scaleway API secret key with read access to billing, and the organization ID it belongs to.

## Setup

1. Install the plugin:
   ```bash
   omarchy plugin add https://github.com/klemengit/omarchy-scaleway-cost.git --enable
   ```
   Or clone it manually into `~/.config/omarchy/plugins/io.github.klemengit.scaleway-cost` and add it to the bar in `~/.config/omarchy/shell.json`, e.g. under `bar.layout.right`:
   ```json
   { "id": "io.github.klemengit.scaleway-cost" }
   ```
2. Get both values from the [Scaleway console](https://console.scaleway.com/):
   - `SCW_API_KEY` — create an API key under **IAM → API Keys**, scoped to (or belonging to a member with) read access to billing. Use the key's **Secret Key**, not the Access Key.
   - `SCW_ORG_ID` — your **Organization ID**, shown under **Organization → Settings** (or in Account settings).
3. Export both in the session environment — e.g. via Hyprland's `envs.local.lua`:
   ```lua
   hl.env("SCW_API_KEY", "<secret key>")
   hl.env("SCW_ORG_ID", "<organization id>")
   ```
   or your shell profile. Both are required; the widget shows an error pill if either is missing.

### Settings

- `refreshIntervalSec` (default `300`) — how often the widget polls Scaleway for fresh data, in seconds.

## How it works

`scaleway-cost.py` calls the Scaleway billing API (`consumptions` and `invoices` endpoints) and prints a single JSON line. `BarWidget.qml` runs the script on a timer, parses the JSON, and renders the pill and popup. The script never raises — any failure (missing API key/org ID, network error, bad response) still prints valid JSON with `"ok": false`, so the widget shows an error state instead of taking the bar down.
