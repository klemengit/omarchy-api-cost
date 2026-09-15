# Scaleway Cost

An [Omarchy](https://omarchy.org/) bar plugin that shows your current-month Scaleway net spend. Click the pill to open a popup with a full cost dashboard — no separate TUI or terminal needed.

The popup shows:

- **Summary** — total net spend, spend before credits, and free-tier credit applied.
- **Breakdown by resource** — every billed line item this month, sorted by cost, with category and quantity.
- **Recent invoices** — the last three invoices with period, total, and state.

Right-click the pill (or use the refresh button in the popup) to force an immediate refresh; otherwise it polls on a timer.

## Setup

1. Clone this plugin into `~/.config/omarchy/plugins/io.github.klemengit.scaleway-cost` (or symlink it there, as in this repo's own layout).
2. Add it to the bar in `~/.config/omarchy/shell.json`, e.g. under `bar.layout.right`:
   ```json
   { "id": "io.github.klemengit.scaleway-cost" }
   ```
3. Export a Scaleway API key as `SCW_API_KEY` in the session environment (e.g. via Hyprland's `envs.local.lua` or your shell profile). Read-only billing access is sufficient.
4. Optionally set `SCW_ORG_ID` if it differs from the key's default organization.

### Settings

- `refreshIntervalSec` (default `300`) — how often the widget polls Scaleway for fresh data, in seconds.

## How it works

`scaleway-cost.py` calls the Scaleway billing API (`consumptions` and `invoices` endpoints) and prints a single JSON line. `BarWidget.qml` runs the script on a timer, parses the JSON, and renders the pill and popup. The script never raises — any failure (missing API key, network error, bad response) still prints valid JSON with `"ok": false`, so the widget shows an error state instead of taking the bar down.
