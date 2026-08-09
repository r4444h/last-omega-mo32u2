# Security Policy

## Supported platforms

- **Windows 11** only (current)
- Stream Dock / MiraBox desktop host
- Gigabyte **MO32U2** (primary)

## Reporting a vulnerability

Please **do not** open a public issue for security problems that could affect other users’ machines (for example, unsafe PowerShell invocation or path injection).

Email the maintainer listed in the GitHub profile / release notes, or open a **private** security advisory on GitHub if enabled.

## Scope notes

This plugin runs local PowerShell helpers and talks to monitor HID/DDC interfaces.
It does not phone home. Treat untrusted forks like any other local automation tool.
