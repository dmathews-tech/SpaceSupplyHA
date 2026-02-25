# SpaceSupplyHA

Home Assistant configuration snapshot for SpaceSupply projectors and control dashboards.

## Included
- `ha/automations.yaml`
- `ha/scripts.yaml`
- `ha/lovelace.dashboard_mars.json`
- `ha/lovelace.overview_status.json`
- `ha/lovelace_dashboards.json`

## Why this scope
This captures the active control logic and UI mappings for projector automation and dashboard operations without exporting secrets, logs, or full Home Assistant storage internals.

## Notes
- Canonical projector IPs:
  - Epson A: `192.168.0.11`
  - Epson B: `192.168.0.12`
- Mars p6/p7 panel controls normalized to Android/Epson play path.
