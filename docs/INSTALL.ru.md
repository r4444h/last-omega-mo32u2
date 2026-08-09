# Установка

**Языки:** [English](INSTALL.md) · [Русский](INSTALL.ru.md) · [中文](INSTALL.zh-CN.md)

## Быстрая установка (Windows 11)

1. Скачайте **`LastOmega-*-windows.zip`** из [Releases](../../releases/latest)
2. Полностью закройте **Stream Dock**
3. Распакуйте папку `com.mirabox.streamdock.lastomega.sdPlugin`
4. Скопируйте её в:

```text
%APPDATA%\HotSpot\StreamDock\plugins\
```

5. Запустите Stream Dock → категория **Last Omega**

```powershell
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```

## Требования

- Только **Windows 11**
- **MiraBox N4 Pro** (Stream Dock)
- Stream Dock ≥ **3.10.188.226**
- Монитор **Gigabyte MO32U2**
- Gigabyte Control Center / Sidekick (прицел и «Графика»)

## Удаление

Удалите папку плагина из `%APPDATA%\HotSpot\StreamDock\plugins\`.
