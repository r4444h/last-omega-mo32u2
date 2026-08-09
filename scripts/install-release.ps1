#Requires -Version 5.1
<#
.SYNOPSIS
  Installs a Last Omega release zip into Stream Dock plugins.

.EXAMPLE
  .\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ZipPath,
  [switch]$NoRestart,
  [string]$PluginsDir = "",
  [string]$StreamDockExe = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ZipPath)) {
  throw "Zip not found: $ZipPath"
}

if (-not $PluginsDir) {
  $PluginsDir = Join-Path $env:APPDATA "HotSpot\StreamDock\plugins"
}
if (-not (Test-Path $PluginsDir)) {
  New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null
}

if (-not $StreamDockExe) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\StreamDock\StreamDock.exe",
    "$env:ProgramFiles\StreamDock\StreamDock.exe"
  )
  $StreamDockExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

Write-Host "=== Last Omega install-release ===" -ForegroundColor Cyan
Write-Host "Zip    : $ZipPath"
Write-Host "Target : $PluginsDir"

# Stop host so plugin folder is not locked
Get-Process -Name "StreamDock", "node20" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$temp = Join-Path $env:TEMP ("lastomega-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $temp -Force
  $plugin = Get-ChildItem -LiteralPath $temp -Directory -Recurse -Filter "com.mirabox.streamdock.lastomega.sdPlugin" |
    Select-Object -First 1
  if (-not $plugin) {
    # Zip may contain the folder at top level already matched
    $direct = Join-Path $temp "com.mirabox.streamdock.lastomega.sdPlugin"
    if (Test-Path $direct) {
      $plugin = Get-Item $direct
    }
  }
  if (-not $plugin) {
    throw "com.mirabox.streamdock.lastomega.sdPlugin not found inside zip"
  }

  $dest = Join-Path $PluginsDir "com.mirabox.streamdock.lastomega.sdPlugin"
  if (Test-Path $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
  }
  Copy-Item -LiteralPath $plugin.FullName -Destination $dest -Recurse -Force
  Write-Host "Installed → $dest" -ForegroundColor Green
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $NoRestart) {
  if (-not $StreamDockExe -or -not (Test-Path $StreamDockExe)) {
    Write-Host "StreamDock.exe not found — start the app manually." -ForegroundColor Yellow
  } else {
    Start-Process -FilePath $StreamDockExe
    Write-Host "Stream Dock started. Open category 'Last Omega'." -ForegroundColor Green
  }
}
