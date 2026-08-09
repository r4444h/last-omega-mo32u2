# Install guide

Step-by-step install for the MiraBox / Stream Dock community package.

**Languages:** [English](INSTALL.md) · [Русский](INSTALL.ru.md) · [中文](INSTALL.zh-CN.md)

## Quick install (Windows 11)

1. Download **`LastOmega-*-windows.zip`** from [GitHub Releases](../../releases/latest)
2. Fully quit **Stream Dock**
3. Extract so you have:

```text
com.mirabox.streamdock.lastomega.sdPlugin\
  manifest.json
  plugin\
  propertyInspector\
  ...
```

4. Copy that folder to:

```text
%APPDATA%\HotSpot\StreamDock\plugins\
```

Full path example:

```text
C:\Users\<You>\AppData\Roaming\HotSpot\StreamDock\plugins\com.mirabox.streamdock.lastomega.sdPlugin
```

5. Start Stream Dock → open category **Last Omega**
6. Drop actions on Keys / Knobs (Brightness & Picture Mode love the dials)

## PowerShell helper

From a clone of this repo:

```powershell
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```

## Requirements checklist

- [ ] Windows **11**
- [ ] **MiraBox N4 Pro** (Stream Dock)
- [ ] Stream Dock app ≥ **3.10.188.226**
- [ ] Gigabyte **MO32U2**
- [ ] Gigabyte Control Center / Sidekick (for crosshair & picture mode)

## Uninstall

Delete:

```text
%APPDATA%\HotSpot\StreamDock\plugins\com.mirabox.streamdock.lastomega.sdPlugin
```
