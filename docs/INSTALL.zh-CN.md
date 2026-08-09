# 安装说明

**语言：** [English](INSTALL.md) · [Русский](INSTALL.ru.md) · [中文](INSTALL.zh-CN.md)

## 快速安装（仅 Windows 11）

1. 从 [Releases](../../releases/latest) 下载 **`LastOmega-*-windows.zip`**
2. 完全退出 **Stream Dock**
3. 解压得到文件夹 `com.mirabox.streamdock.lastomega.sdPlugin`
4. 复制到：

```text
%APPDATA%\HotSpot\StreamDock\plugins\
```

5. 启动 Stream Dock → 分类 **Last Omega**

```powershell
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```

## 环境要求

- **仅 Windows 11**
- **MiraBox N4 Pro**（Stream Dock）
- Stream Dock ≥ **3.10.188.226**
- 显示器 **Gigabyte MO32U2**
- Gigabyte Control Center / Sidekick（准星与图像模式）

## 卸载

删除 `%APPDATA%\HotSpot\StreamDock\plugins\` 下的插件文件夹即可。
