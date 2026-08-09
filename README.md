<p align="center">
  <img src="assets/banner.svg" alt="Last Omega — MiraBox N4 Pro × Gigabyte MO32U2" width="100%"/>
</p>

<h1 align="center">Last Omega</h1>

<p align="center">
  <strong>Your MO32U2. Your knobs. No OSD diving.</strong><br/>
  A Stream Dock plugin for <strong>MiraBox N4 Pro</strong>, purpose-built for the
  <strong>Gigabyte MO32U2</strong> monitor —
  HDR, brightness, crosshair and picture modes without digging through the OSD.
</p>

<p align="center">
  <a href="#install"><img alt="Install" src="https://img.shields.io/badge/install-Windows%20zip-5CFFB0?style=for-the-badge"/></a>
  <a href="docs/README.ru.md"><img alt="RU" src="https://img.shields.io/badge/docs-Русский-4DB8FF?style=for-the-badge"/></a>
  <a href="docs/README.zh-CN.md"><img alt="ZH" src="https://img.shields.io/badge/docs-中文-4DB8FF?style=for-the-badge"/></a>
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-0B1220?style=for-the-badge"/></a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/OS-Windows%2011%20only-critical"/>
  <img alt="Host" src="https://img.shields.io/badge/Stream%20Dock-%E2%89%A5%203.10.188.226-blue"/>
  <img alt="Runtime" src="https://img.shields.io/badge/Node.js-20-brightgreen"/>
  <img alt="Device" src="https://img.shields.io/badge/Device-MiraBox%20N4%20Pro-blueviolet"/>
  <img alt="Monitor" src="https://img.shields.io/badge/Monitor-Gigabyte%20MO32U2-informational"/>
  <img alt="Version" src="https://img.shields.io/badge/plugin-v0.5.5-orange"/>
</p>

> Built and validated on **MiraBox N4 Pro** + **Gigabyte MO32U2**.  
> Gifted to the **MiraBox / Stream Dock** community.  
> Languages: **[English](README.md)** · **[Русский](docs/README.ru.md)** · **[中文](docs/README.zh-CN.md)**

**Credits:** directed & product owner — **Rustam**; implementation — **Cursor (AI coding assistant)**.  
**License:** [MIT](LICENSE) — free for everyone: use, share, fork, and modify however you like.

---

## Why this exists

The **Gigabyte MO32U2** is a serious gaming / creator panel. Its OSD is not.  
The **MiraBox N4 Pro** (Stream Dock) has real knobs and keys sitting on your desk.

**Last Omega** connects that exact pair: panel controls on the N4 Pro — no digging through the monitor menu.

| Action | What it does |
|--------|----------------|
| **HDR Toggle** | Flip Windows HDR for the MO32U2 |
| **Brightness** | SDR `%` or HDR SDR-content **nits** — one knob, correct unit |
| **Crosshair** | On-panel AIM via Gigabyte Sidekick HID |
| **Picture Mode** | Cycle **Graphics** profiles (STD / FPS / MOBA / …) with preview-then-apply |

Keep your aim, keep your hands on the dials, keep the monitor menu closed.

---

## Gallery

Drop photos / clips here when ready — filenames match [`assets/screenshots/CAPTIONS.md`](assets/screenshots/CAPTIONS.md):

| File | Idea |
|------|------|
| `assets/screenshots/01-hero-desk.jpg` | Desk hero — **MiraBox N4 Pro** + **MO32U2** |
| `assets/screenshots/02-brightness-knob.jpg` | N4 Pro brightness dial (`24%` / `180n`) |
| `assets/screenshots/03-picture-mode.jpg` | N4 Pro Picture Mode dial (STD → FPS → …) |
| `assets/screenshots/04-hdr-crosshair.jpg` | N4 Pro keys: HDR + Crosshair |
| `assets/screenshots/05-install.jpg` | Install zip / plugins folder |

After you add images, uncomment (or paste) in this README:

```markdown
<p align="center">
  <img src="assets/screenshots/01-hero-desk.jpg" alt="Last Omega on MiraBox + MO32U2" width="80%"/>
</p>

<p align="center">
  <img src="assets/screenshots/02-brightness-knob.jpg" width="32%"/>
  <img src="assets/screenshots/03-picture-mode.jpg" width="32%"/>
  <img src="assets/screenshots/04-hdr-crosshair.jpg" width="32%"/>
</p>
```

**Video (optional):** upload to YouTube / Bilibili / Streamable, then add under Gallery:

```markdown
<p align="center">
  <a href="https://youtu.be/YOUR_ID"><img src="assets/screenshots/01-hero-desk.jpg" alt="Watch demo" width="80%"/></a>
</p>

> Demo (60–90s): knobs → brightness → picture mode → HDR — no OSD.
```

Do **not** commit huge raw `.mp4` into git (keep under ~5–10 MB if you must). Prefer an external host + thumbnail in `assets/screenshots/`.

---

## Requirements

| Item | Version / note |
|------|----------------|
| **OS** | **Windows 11 only** (not tested / not supported on Windows 10) |
| **Host device** | **MiraBox N4 Pro** (Stream Dock) — primary; other Stream Dock devices with Keys/Knobs may work |
| **Host app** | Stream Dock desktop **≥ 3.10.188.226** |
| **Plugin runtime** | **Node.js 20** (bundled with Stream Dock as `node20`) |
| **Monitor** | **Gigabyte MO32U2** — primary validated display |
| **Sidekick** | Gigabyte Control Center / OSD Sidekick (crosshair + picture mode) |
| **PowerShell** | 5.1+ (ships with Windows 11) |

> Packaged releases already include `node_modules` (`ws`). End users do **not** need to install Node separately.

### Hardware this project is for

| Piece | Model | Role |
|-------|--------|------|
| Controller | **MiraBox N4 Pro** | Keys + Knobs (Brightness & Picture Mode shine on dials) |
| Display | **Gigabyte MO32U2** | HDR, DDC brightness, Sidekick HID crosshair & Graphics modes |

---

## Install

See also the full guide: **[docs/INSTALL.md](docs/INSTALL.md)** ([RU](docs/INSTALL.ru.md) · [中文](docs/INSTALL.zh-CN.md))

### Option A — Download the install package (recommended)

1. Open **[Releases](../../releases/latest)** and download  
   `LastOmega-<version>-windows.zip`
2. Quit Stream Dock
3. Unpack so you get a folder named  
   `com.mirabox.streamdock.lastomega.sdPlugin`
4. Copy that folder into:

```text
%APPDATA%\HotSpot\StreamDock\plugins\
```

5. Start Stream Dock → category **Last Omega**

Or from PowerShell (after downloading the zip):

```powershell
Expand-Archive .\LastOmega-0.5.5-windows.zip -DestinationPath "$env:TEMP\lastomega"
Copy-Item "$env:TEMP\lastomega\com.mirabox.streamdock.lastomega.sdPlugin" `
  "$env:APPDATA\HotSpot\StreamDock\plugins\" -Recurse -Force
```

### Option B — One-shot install from a release asset

```powershell
# From a cloned repo, after you placed the zip under dist\
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```

### Option C — Build from source

See [Build](#build) below, then `.\scripts\deploy.ps1`.

---

## Build

```powershell
# 1) Dependencies (Node 20+)
cd com.mirabox.streamdock.lastomega.sdPlugin\plugin
npm ci
cd ..\..\..

# 2) Dev deploy into Stream Dock (restarts the app)
.\scripts\deploy.ps1

# 3) Create the community install zip → dist\
.\scripts\pack.ps1
```

### Stack

| Layer | Tech |
|-------|------|
| Plugin host API | Stream Dock SDK (`ws` WebSocket, Node 20) |
| HDR | Windows DisplayConfig (PowerShell) |
| Brightness | DDC/CI + HDR SDR white-level APIs |
| Crosshair / Picture | Gigabyte OSD Sidekick USB HID (`VID_0BDA&PID_1100`) |
| UI | Transparent keys + dial titles; Property Inspectors (HTML) |

---

## Repository layout

```text
last-omega/
├── README.md / docs/          # EN + RU + ZH
├── assets/                    # Banner + screenshot captions
├── scripts/
│   ├── deploy.ps1             # Dev install
│   ├── pack.ps1               # Release zip for MiraBox users
│   └── install-release.ps1    # Install from zip
├── tools/probes/              # Hardware experiments (not shipped)
├── .github/workflows/         # Release packaging CI
└── com.mirabox.streamdock.lastomega.sdPlugin/
    ├── manifest.json          # v0.5.5 · Node 20
    ├── en.json / ru.json / zh_CN.json
    ├── plugin/                # index.js + *.ps1 helpers + ws
    ├── propertyInspector/     # Per-action settings
    └── static/
```

---

## Screenshot lines (for store / social)

> **Your MO32U2. Your knobs. No OSD diving.**  
> Dial brightness in SDR `%` or HDR nits — same knob, right unit.  
> Preview picture modes while you turn; apply when you pause.

More EN / RU / ZH copy: [`assets/screenshots/CAPTIONS.md`](assets/screenshots/CAPTIONS.md)

Drop real photos into `assets/screenshots/` using the filenames listed there.

---

## Compatibility

| Works today | Notes |
|-------------|--------|
| **MiraBox N4 Pro** | Primary device — validated with Keys + Knobs |
| **Gigabyte MO32U2** | Primary monitor — validated end-to-end |
| Windows **11** | Required |
| Stream Dock host **≥ 3.10.188.226** | Desktop app that drives the N4 Pro |

Other Stream Dock / MiraBox units with Knobs may run the same plugin.  
Other Gigabyte Sidekick panels may work partially — open an issue with your model + VCP/HID notes.

---

## Contributing & license

- Guide: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Security: [`SECURITY.md`](SECURITY.md)
- License: [`MIT`](LICENSE) — **free for everyone**. You may use, copy, modify, merge, publish, and distribute this plugin (including commercial forks) with almost no restrictions — just keep the copyright notice.

### Credits

| Role | Who |
|------|-----|
| Direction, product decisions, testing on **N4 Pro + MO32U2** | **Rustam** |
| Implementation (code, docs, packaging) | **Cursor AI** (Grok), under Rustam’s guidance |

Built as a gift for the MiraBox community — not a locked product.
