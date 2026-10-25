#Requires -Version 5.1
<#
.SYNOPSIS
  Reuse the existing monitor helpers in one Windows PowerShell session.
.DESCRIPTION
  Local JSON lines over redirected stdin/stdout. Only the five fixed helper
  scripts and their documented parameters can be called. No executable is
  generated or downloaded. The host uses RemoteSigned for this process only;
  system policies, Group Policy and antivirus settings are not modified.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$helpers = @{
  hdr = @{ file = 'HdrControl.ps1'; actions = @('status','list','toggle','on','off') }
  brightness = @{ file = 'BrightnessControl.ps1'; actions = @('status','list','set','adjust') }
  crosshair = @{ file = 'CrosshairControl.ps1'; actions = @('status','on','off','toggle','set') }
  pictureMode = @{ file = 'PictureModeControl.ps1'; actions = @('status','list','set','delta') }
  refreshRate = @{ file = 'RefreshRateControl.ps1'; actions = @('status','list') }
}
$counts = @{ requests = 0; brightnessStatus = 0; brightnessSet = 0; pictureStatus = 0 }

function Write-Reply($reply) {
  [Console]::Out.WriteLine(($reply | ConvertTo-Json -Compress -Depth 12))
  [Console]::Out.Flush()
}

# Loads the same maintained interop type as the standalone diagnostic script.
$null = & (Join-Path $PSScriptRoot 'HdrControl.ps1') -Action list
[HdrNative]::StartDisplayWatch()
$reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
try {
  while ($true) {
    $lineTask = $reader.ReadLineAsync()
    while (-not $lineTask.IsCompleted) {
      $handles = [Threading.WaitHandle[]]@(([IAsyncResult]$lineTask).AsyncWaitHandle, [HdrNative]::DisplayChangeSignal)
      if ([Threading.WaitHandle]::WaitAny($handles) -eq 1) { Write-Reply @{ event = 'displayChanged' } }
    }
    $line = $lineTask.GetAwaiter().GetResult()
    $lineTask.Dispose()
    if ($null -eq $line) { break }
    $requestId = $null
    try {
      if ($line.Length -gt 65536) { throw 'Monitor request is too large' }
      $request = $line | ConvertFrom-Json
      $requestId = $request.id
      $counts.requests++
      $kind = [string]$request.kind
      if ($kind -eq 'ping') {
        Write-Reply @{ id = $requestId; result = @{ ok = $true; processId = $PID; counters = $counts } }
        continue
      }
      if (-not $helpers.ContainsKey($kind)) { throw 'Unknown monitor command' }
      $helper = $helpers[$kind]
      $action = if ($request.action) { [string]$request.action } else { 'status' }
      if ($action -notin $helper.actions) { throw 'Unsupported monitor action' }
      $arguments = @{ Action = $action }
      $filter = if ($request.nameFilter) { [string]$request.nameFilter } else { 'MO32U2' }
      if ($kind -ne 'crosshair') { $arguments.NameFilter = $filter }
      switch ($kind) {
        brightness {
          if ($action -eq 'status') { $counts.brightnessStatus++ }
          if ($action -in @('set','adjust')) { $counts.brightnessSet++ }
          foreach ($entry in @(@('value','Value'),@('delta','Delta'),@('stepHdr','StepHdr'),@('stepSdr','StepSdr'))) {
            if ($null -ne $request.($entry[0])) { $arguments[$entry[1]] = $request.($entry[0]) }
          }
          if ($null -ne $request.expectedHdrEnabled) {
            $arguments.ExpectedHdr = if ([bool]$request.expectedHdrEnabled) { 'on' } else { 'off' }
          }
        }
        crosshair {
          if ($null -ne $request.style) { $arguments.Style = [int]$request.style }
          if ($null -ne $request.value) { $arguments.Value = [int]$request.value }
        }
        pictureMode {
          if ($action -eq 'status') { $counts.pictureStatus++ }
          if ($null -ne $request.value) { $arguments.Value = [int]$request.value }
          if ($null -ne $request.delta) { $arguments.Delta = [int]$request.delta }
          $display = [HdrNative]::GetDisplays() | Where-Object { $_.Name -like "*$filter*" -or $_.Path -like "*$filter*" } | Select-Object -First 1
          if ($null -eq $display) { throw 'Active monitor not found' }
          $arguments.KnownHdrEnabled = [bool]$display.HdrEnabled
        }
      }
      $output = @(& (Join-Path $PSScriptRoot $helper.file) @arguments)
      $result = ($output | Where-Object { $_ -is [string] -and $_.Trim().StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
      if ($null -eq $result) { throw 'Monitor helper returned no JSON' }
      Write-Reply @{ id = $requestId; result = $result }
    } catch {
      Write-Reply @{ id = $requestId; result = @{ ok = $false; error = $_.Exception.Message } }
    }
  }
} finally {
  [HdrNative]::StopDisplayWatch()
  $reader.Dispose()
}
