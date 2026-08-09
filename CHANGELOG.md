# Changelog

All notable changes to **Last Omega** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
