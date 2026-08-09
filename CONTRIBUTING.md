# Contributing to Last Omega

Thank you for helping the MiraBox / Stream Dock community.

## Ground rules

- Target hardware today: **Gigabyte MO32U2** on **Windows 11**
- Keep changes focused — one PR, one concern
- Prefer Russian / English issue descriptions; Chinese welcome
- Do not commit runtime caches (`*-state.json`, `ui-state-cache.json`, `*.log`)
- Project is **MIT** — forks and modifications are welcome

This repository was directed by **R4444H** and implemented with **Cursor AI** under his guidance.

## Development setup

1. Windows 11 + Stream Dock **≥ 3.10.188.226**
2. Gigabyte Control Center / Sidekick (for crosshair & picture mode HID)
3. Node.js **20** (Stream Dock ships `node20`; local Node is for `npm install` / packing)

```powershell
cd com.mirabox.streamdock.lastomega.sdPlugin\plugin
npm ci
cd ..\..\..
.\scripts\deploy.ps1
```

## Pack a community install zip

```powershell
.\scripts\pack.ps1
# → dist\LastOmega-0.5.5-windows.zip
```

## Pull requests

1. Fork + branch from `main`
2. Test on a real MO32U2 when touching HID / DDC / HDR paths
3. Update `CHANGELOG.md` under `[Unreleased]` if user-facing
4. Bump `manifest.json` → `Version` when cutting a release

## Code map

| Path | Role |
|------|------|
| `com.mirabox.streamdock.lastomega.sdPlugin/plugin/index.js` | Plugin logic |
| `*.ps1` next to it | Win32 / HID / DDC helpers |
| `propertyInspector/` | Action settings UI |
| `scripts/deploy.ps1` | Dev install into `%APPDATA%\HotSpot\StreamDock\plugins` |
| `scripts/pack.ps1` | Release zip for GitHub Releases |
| `tools/probes/` | Dev-only hardware experiments (not shipped) |
