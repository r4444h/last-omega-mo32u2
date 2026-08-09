# Last Omega

<p align="center"><strong>专为 Gigabyte MO32U2 — 旋钮直达，告别 OSD。</strong></p>

面向 **MiraBox N4 Pro**（Stream Dock）的插件，专为 **Gigabyte MO32U2** 显示器打造：
HDR、亮度、准星与图像模式，无需再钻进屏幕菜单。

实测组合：**MiraBox N4 Pro** + **Gigabyte MO32U2**。

[English](../README.md) · [Русский](README.ru.md) · **中文**

---

## 功能

| 动作 | 说明 |
|------|------|
| **HDR** | 开关 Windows HDR（针对 MO32U2） |
| **亮度** | SDR 用 `%`，HDR 下 SDR 内容用 **nits**；同一旋钮 |
| **准星** | 通过 Sidekick HID 控制面板准星 |
| **图像模式** | 转动预览，停转后写入 Graphics / Picture Mode |

## 截图 / 视频

把截图放到 `assets/screenshots/`（文件名与文案见 [`../assets/screenshots/CAPTIONS.md`](../assets/screenshots/CAPTIONS.md)）。  
README 插入方式与 YouTube/Bilibili 链接见英文主文档 [`../README.md`](../README.md) 的 **Gallery** 一节。

## 环境要求

- **仅支持 Windows 11**
- 设备：**MiraBox N4 Pro**（Stream Dock；主要目标）
- Stream Dock 应用 **≥ 3.10.188.226**
- 插件运行时：**Node.js 20**（随 Stream Dock 自带）
- 显示器：**Gigabyte MO32U2**（主要验证型号）
- Gigabyte Control Center / OSD Sidekick（准星与图像模式）

### 硬件组合

| 部件 | 型号 |
|------|------|
| 控制器 | **MiraBox N4 Pro** — 按键与旋钮 |
| 显示器 | **Gigabyte MO32U2** — HDR、亮度、准星、图像模式 |

## 安装成品包

1. 从 [Releases](../../releases/latest) 下载 `LastOmega-<version>-windows.zip`
2. 退出 Stream Dock
3. 将文件夹 `com.mirabox.streamdock.lastomega.sdPlugin` 解压到：

```text
%APPDATA%\HotSpot\StreamDock\plugins\
```

4. 启动 Stream Dock → 分类 **Last Omega**

```powershell
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```

## 从源码构建

```powershell
cd com.mirabox.streamdock.lastomega.sdPlugin\plugin
npm ci
cd ..\..\..
.\scripts\deploy.ps1          # 开发安装
.\scripts\pack.ps1            # 社区安装包 → dist\
```

## 技术栈

- Stream Dock SDK（WebSocket `ws`，Node 20）
- HDR — Windows DisplayConfig
- 亮度 — DDC/CI + HDR 下 SDR 白电平 API
- 准星 / 图像模式 — Sidekick USB HID（`VID_0BDA&PID_1100`）

## 截图文案

> **专为 Gigabyte MO32U2 — 旋钮直达，告别 OSD。**  
> 同一亮度旋钮：SDR 用 `%`，HDR 用 nits。  
> 转动即预览图像模式，停转后再写入。

完整文案（英/俄/中）：[`../assets/screenshots/CAPTIONS.md`](../assets/screenshots/CAPTIONS.md)

## 许可

[MIT](../LICENSE) — **对所有人免费**：可下载、使用、修改、再分发（含商业分支），只需保留版权声明。

### 致谢

| 角色 | 人员 |
|------|------|
| 产品方向、决策、**N4 Pro + MO32U2** 实测 | **Rustam** |
| 实现（代码、文档、打包） | **Cursor AI**（Grok），由 Rustam 指导 |

献给 MiraBox 社区。
