#Requires -Version 5.1
<#
.SYNOPSIS
  Builds a MiraBox / Stream Dock install zip under dist\.

.DESCRIPTION
  Produces: dist\LastOmega-<version>-windows.zip
  containing com.mirabox.streamdock.lastomega.sdPlugin\ (ready to copy into plugins).

.EXAMPLE
  .\scripts\pack.ps1

.EXAMPLE
  .\scripts\pack.ps1 -SkipNpm
#>
[CmdletBinding()]
param(
  [switch]$SkipNpm,
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repoRoot "com.mirabox.streamdock.lastomega.sdPlugin"
$pluginCode = Join-Path $pluginRoot "plugin"
$manifestPath = Join-Path $pluginRoot "manifest.json"

if (-not (Test-Path $manifestPath)) {
  throw "manifest.json not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.Version
if (-not $version) { $version = "0.0.0" }

if (-not $OutDir) {
  $OutDir = Join-Path $repoRoot "dist"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "=== Last Omega pack ===" -ForegroundColor Cyan
Write-Host "Version : $version"
Write-Host "Plugin  : $pluginRoot"

if (-not $SkipNpm) {
  Write-Host "npm ci (Node 20 dependencies)..."
  Push-Location $pluginCode
  try {
    if (-not (Test-Path "package-lock.json")) {
      npm install --omit=dev
    } else {
      npm ci --omit=dev
    }
    if ($LASTEXITCODE -ne 0) { throw "npm failed with exit $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

$stage = Join-Path $OutDir "_stage"
$stagePlugin = Join-Path $stage "com.mirabox.streamdock.lastomega.sdPlugin"
if (Test-Path $stage) {
  Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stagePlugin -Force | Out-Null

Write-Host "Staging plugin (excluding caches / logs / probes)..."
$excludeDirs = @(
  "lastomega-debug.log",
  "ui-state-cache.json",
  "picture-mode-state.json",
  "picture-modes-cache.json",
  "crosshair-state.json"
)

# Robocopy mirrors the plugin; then delete runtime junk.
& robocopy $pluginRoot $stagePlugin /E /NFL /NDL /NJH /NJS /nc /ns /np `
  /XD "node_modules\.cache" | Out-Null
# robocopy exit codes 0-7 are success
if ($LASTEXITCODE -ge 8) {
  throw "robocopy failed with exit $LASTEXITCODE"
}

Get-ChildItem -LiteralPath (Join-Path $stagePlugin "plugin") -File -ErrorAction SilentlyContinue |
  Where-Object { $excludeDirs -contains $_.Name -or $_.Extension -eq ".log" } |
  Remove-Item -Force -ErrorAction SilentlyContinue

# Ensure node_modules/ws exists
$wsDir = Join-Path $stagePlugin "plugin\node_modules\ws"
if (-not (Test-Path $wsDir)) {
  throw "node_modules/ws missing after npm - cannot ship a runnable plugin"
}

$zipName = "LastOmega-$version-windows.zip"
$zipPath = Join-Path $OutDir $zipName
if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Write-Host "Compressing $zipName ..."
Compress-Archive -Path $stagePlugin -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force

# Also emit a copy with .streamDockPlugin extension (some hosts expect it)
$sdpPath = Join-Path $OutDir ("LastOmega-$version-windows.streamDockPlugin")
Copy-Item -LiteralPath $zipPath -Destination $sdpPath -Force

# SHA256 for release notes
$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$shaFile = Join-Path $OutDir ("LastOmega-$version-windows.sha256")
Set-Content -LiteralPath $shaFile -Value "$sha  $zipName" -Encoding ASCII

Write-Host ""
Write-Host "Packed:" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host "  $sdpPath"
Write-Host "  $shaFile"
Write-Host "SHA256: $sha"
Write-Host ""
Write-Host "Install: unpack the zip into %APPDATA%\HotSpot\StreamDock\plugins\"
