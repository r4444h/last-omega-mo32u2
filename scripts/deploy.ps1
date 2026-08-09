#Requires -Version 5.1
<#
.SYNOPSIS
  Copies the Last Omega plugin into Stream Dock and restarts the app.

.EXAMPLE
  .\scripts\deploy.ps1

.EXAMPLE
  .\scripts\deploy.ps1 -NoRestart
#>
[CmdletBinding()]
param(
  [switch]$NoRestart,
  [string]$PluginSource = "",
  [string]$PluginsDir = "",
  [string]$StreamDockExe = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $PluginSource) {
  $PluginSource = Join-Path $repoRoot "com.mirabox.streamdock.lastomega.sdPlugin"
}
if (-not $PluginsDir) {
  $PluginsDir = Join-Path $env:APPDATA "HotSpot\StreamDock\plugins"
}
if (-not $StreamDockExe) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\StreamDock\StreamDock.exe",
    "$env:ProgramFiles\StreamDock\StreamDock.exe"
  )
  $StreamDockExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$pluginName = Split-Path -Leaf $PluginSource
$dest = Join-Path $PluginsDir $pluginName

Write-Host "=== Stream Dock deploy ===" -ForegroundColor Cyan
Write-Host "Source : $PluginSource"
Write-Host "Target : $dest"

if (-not (Test-Path $PluginSource)) {
  throw "Plugin folder not found: $PluginSource"
}
if (-not (Test-Path (Join-Path $PluginSource "manifest.json"))) {
  throw "manifest.json missing in: $PluginSource"
}
if (-not (Test-Path $PluginsDir)) {
  New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null
  Write-Host "Created plugins folder: $PluginsDir"
}

function Stop-StreamDock {
  $procs = @(
    Get-Process -Name "StreamDock" -ErrorAction SilentlyContinue
    Get-Process -Name "node20" -ErrorAction SilentlyContinue
  )
  if (-not $procs) {
    Write-Host "Stream Dock is not running."
    return
  }

  Write-Host "Stopping Stream Dock / node20 (PID: $($procs.Id -join ', '))..."
  foreach ($p in $procs) {
    try {
      if ($p.ProcessName -eq "StreamDock") {
        $p.CloseMainWindow() | Out-Null
      }
    } catch {}
  }

  $deadline = (Get-Date).AddSeconds(8)
  while ((Get-Date) -lt $deadline) {
    $alive = Get-Process -Name "StreamDock", "node20" -ErrorAction SilentlyContinue
    if (-not $alive) { break }
    Start-Sleep -Milliseconds 250
  }

  $still = Get-Process -Name "StreamDock", "node20" -ErrorAction SilentlyContinue
  if ($still) {
    Write-Host "Force-stopping leftover processes..."
    $still | Stop-Process -Force
    Start-Sleep -Milliseconds 800
  }
}

function Copy-Plugin {
  if (Test-Path $dest) {
    Write-Host "Removing previous install..."
    Remove-Item -LiteralPath $dest -Recurse -Force
  }

  Write-Host "Copying plugin..."
  Copy-Item -LiteralPath $PluginSource -Destination $dest -Recurse -Force
  Write-Host "Copied to: $dest" -ForegroundColor Green
}

function Start-StreamDockApp {
  if (-not $StreamDockExe -or -not (Test-Path $StreamDockExe)) {
    throw "StreamDock.exe not found. Pass -StreamDockExe."
  }

  Write-Host "Starting Stream Dock: $StreamDockExe"
  Start-Process -FilePath $StreamDockExe
}

Stop-StreamDock
Copy-Plugin

if ($NoRestart) {
  Write-Host "Done (no restart)." -ForegroundColor Yellow
  exit 0
}

Start-StreamDockApp
Write-Host "Done. Look for category 'Last Omega' in Stream Dock." -ForegroundColor Green
