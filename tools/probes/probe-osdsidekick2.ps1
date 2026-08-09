$ErrorActionPreference = "Continue"
$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
[Environment]::CurrentDirectory = $sidekick
Set-Location $sidekick
$env:PATH = "$sidekick;$env:PATH"
Add-Type -Path "$sidekick\OSDSidekick.dll"

Write-Output "Try DDC.DLL_init"
try { Write-Output ([OSDSidekick.DDC]::DLL_init()) } catch { Write-Output $_.Exception.ToString() }
Write-Output "Try RTK_HUB.DLL_init"
try { Write-Output ([OSDSidekick.RTK_HUB]::DLL_init()) } catch { Write-Output $_.Exception.ToString() }
Write-Output "Try dllexp_LibInitial"
try { Write-Output ([OSDSidekick.DDC]::dllexp_LibInitial()) } catch { Write-Output $_.Exception.ToString() }

# Common Realtek VID/PID for Gigabyte OSD: 0BDA / 1100
$vid = [uint16]0x0BDA
$pid = [uint16]0x1100
Write-Output "RTK_Get_MultiHID vid=$vid pid=$pid"
try {
  $n = [OSDSidekick.DDC]::RTK_Get_MultiHID($vid, $pid)
  Write-Output "count=$n"
  for ($i=0; $i -lt [Math]::Max($n,1); $i++) {
    $h = [OSDSidekick.DDC]::RTK_Open_mutiHID($i)
    Write-Output " open[$i]=$h"
  }
} catch { Write-Output $_.Exception.ToString() }

# Inspect OSD_Interface public API for enumeration
$oi = [OSDSidekick.OSD_Interface]
Write-Output "==== OSD_Interface ctors/methods ===="
$oi.GetConstructors() | ForEach-Object {
  $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
  Write-Output "ctor($ps)"
}
$oi.GetMethods([Reflection.BindingFlags]'Public,Instance,DeclaredOnly') | ForEach-Object {
  $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
  Write-Output "$($_.ReturnType.Name) $($_.Name)($ps)"
}

# Try construct and GetMonitorAllInfo
try {
  $inst = [Activator]::CreateInstance($oi)
  Write-Output "Created OSD_Interface"
  $cnt = $inst.GetMonitorAllInfo()
  Write-Output "GetMonitorAllInfo=$cnt"
  Write-Output "Monitor_act_Index=$($inst.Monitor_act_Index)"
  Write-Output "Crosshair_Index=$($inst.Crosshair_Index)"
  $cur = $inst.GetCurrentCrosshair()
  Write-Output "GetCurrentCrosshair=$cur"
} catch { Write-Output "OSD_Interface fail: $($_.Exception.ToString())" }

# List DDC P/Invoke dll names via custom attrs
Write-Output "==== DllImport targets on DDC ===="
[OSDSidekick.DDC].GetMethods([Reflection.BindingFlags]'Public,NonPublic,Static,DeclaredOnly') |
  ForEach-Object {
    $attr = $_.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false)
    if ($attr.Count -gt 0 -and ($_.Name -match 'Cross|AIM|Init|RTK|Open|Close|GetSoc|Multi')) {
      Write-Output "$($_.Name) -> $($attr[0].Value) EntryPoint=$($attr[0].EntryPoint)"
    }
  } | Select-Object -First 40
