# Last Omega

<p align="center"><strong>专为 Gigabyte MO32U2 — 旋钮直达，告别 OSD。</strong></p>

面向 **MiraBox N4 Pro**（Stream Dock）的插件，专为 **Gigabyte MO32U2** 显示器打造：
HDR、亮度、准星、图像模式与刷新率，无需再钻进屏幕菜单。

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
| **刷新率** | 在按键上显示当前 Hz（如 `240Hz`），轮询间隔可配置 |

## 截图

<p align="center">
  <img src="../assets/screenshots/01-streamdock-keys.png" alt="Last Omega 按键" width="32%"/>
  <img src="../assets/screenshots/02-streamdock-knobs.png" alt="Last Omega 旋钮" width="32%"/>
  <img src="../assets/screenshots/03-streamdock-hdr.png" alt="HDR 设置" width="32%"/>
</p>

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
| 显示器 | **Gigabyte MO32U2** — HDR、亮度、准星、图像模式、刷新率 |

## 安装成品包

完整步骤：**[INSTALL.zh-CN.md](INSTALL.zh-CN.md)**（[EN](INSTALL.md) · [RU](INSTALL.ru.md)）

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
- 刷新率 — DisplayConfig Hz，对齐常见面板刷新率

## 许可

[MIT](../LICENSE) — **对所有人免费**：可下载、使用、修改、再分发（含商业分支），只需保留版权声明。

### 致谢

| 角色 | 人员 |
|------|------|
| 产品方向、决策、**N4 Pro + MO32U2** 实测 | **R4444H** |
| 实现（代码、文档、打包） | **Cursor AI**，由 R4444H 指导 |

以 **[MIT 许可证](../LICENSE)** 发布 — 可自由使用、复制、修改、合并、发布、分发、再许可和/或出售本软件的副本。
