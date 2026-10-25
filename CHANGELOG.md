# Changelog

All notable changes to **Last Omega** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Press the brightness key or dial to toggle HDR; turn the dial to adjust monitor brightness as before.
- One Windows PowerShell session reuses the existing monitor helpers and loads their Win32 interop types once per session. No separate EXE, MSBuild step or executable-generating build script is required.

### Changed
- Visible controls for the same monitor share background reads. Brightness defaults to 15 seconds, HDR and picture metadata to 30 seconds, refresh rate to 60 seconds. Display changes trigger immediate refreshes.
- Hardware commands run one at a time, interactive writes pass queued background reads, and failed polls back off without overlapping or building up a queue.
- Picture status uses the last successful explicit selection without repeatedly querying a remapped DDC value. UI cache writes are atomic, combined, and skipped when the state has not changed.
- The session accepts only fixed monitor commands over local stdin/stdout and uses RemoteSigned for its process. Developer deployment preserves monitor state files.

### Fixed
- Brightness now controls the monitor's 0–100 setting in both SDR and HDR. HDR changes immediately refresh neighboring brightness controls; Windows SDR white level is no longer used as HDR monitor brightness.
- Brightness faces show SDR/HDR, legacy nits settings are migrated, and pending adjustments cannot carry an old mode's value into a new HDR mode.
- AIM now falls back to the MO32U2 Sidekick DDC command when USB HID is unavailable, including HDMI connections. DDC status and writes are checked against the monitor.
- AIM commands run in order, and helper errors reach the action settings instead of losing their diagnostic message.

## [0.5.5] - 2026-08-09

### Added
- Refresh Rate Key — show current panel Hz (`240Hz`), configurable poll interval
- Plugin Omega icon (`static/icon.png`) for category and actions

### Fixed
- Refresh rate rounding snaps to common panel rates (e.g. 239.998 → 240)

### Changed
- Docs (EN / RU / ZH) include Refresh Rate / Герцовка / 刷新率

## [0.5.4] - 2026-08-09

### Added
- Picture Mode (Graphics) knob with debounce-commit (preview while turning, set after pause)
- Crosshair toggle via Gigabyte OSD Sidekick HID
- Shared UI state cache to reduce flicker on scene switches
- Knob title rendering (Stream Dock keeps dial labels across scenes)
- EN / RU / zh_CN plugin locales
- Production README gallery screenshots + PNG banner

### Fixed
- Picture Mode dial sticking after the first hardware set (state object / modes list race)
- Brightness / Picture Mode skipping modes on fast dial ticks
- Scene-switch blanking on Keys/Knobs

### Changed
- Brightness uses SDR `%` / HDR `nits` labels on Keys; Knobs use titles

## [0.2.0] - 2026-08-09

### Added
- HDR toggle via Windows DisplayConfig
- Brightness Key/Knob (DDC + HDR SDR-content luminance)

[0.5.5]: #v055
[0.5.4]: #v054
[0.2.0]: #v020
