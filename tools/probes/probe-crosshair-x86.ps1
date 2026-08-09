$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
# Note: on 32-bit process, Program Files may redirect - use explicit path
Set-Location $sidekick
$env:PATH = "$sidekick;" + $env:PATH
[Environment]::CurrentDirectory = $sidekick
Write-Output "Is64BitProcess=$([Environment]::Is64BitProcess)"
Add-Type -Path "$sidekick\OSDSidekick.dll"
[void][OSDSidekick.DDC]::DLL_init()
$vendorId = [uint16]0x0BDA
$productId = [uint16]0x1100
$n = [OSDSidekick.DDC]::RTK_Get_MultiHID($vendorId, $productId)
Write-Output "MultiHID=$n"
$h = [OSDSidekick.DDC]::RTK_Open_mutiHID(0)
Write-Output "Open=$h"
$mhType = [OSDSidekick.DDC].GetNestedType("Monitor_Handle")
$mh = [Activator]::CreateInstance($mhType)
$mh.Realtek = $h
$model = New-Object byte[] 64
[OSDSidekick.DDC]::GetSocModel_Realtek($mh, $model)
Write-Output ("Model=" + [Text.Encoding]::ASCII.GetString($model).Trim([char]0))
try {
  $c = [OSDSidekick.DDC]::GetCrosshair($mh, 0)
  Write-Output "GetCrosshair ddctype0=$c"
} catch { Write-Output "GetCrosshair ERR: $($_.Exception.Message)" }
try {
  [OSDSidekick.DDC]::SetCrosshair1ON($mh, 0)
  Write-Output "SetCrosshair1ON ok"
  Start-Sleep -Milliseconds 800
  Write-Output ("GetCrosshair after=" + [OSDSidekick.DDC]::GetCrosshair($mh, 0))
  [OSDSidekick.DDC]::SetCrosshairOFF($mh, 0)
  Write-Output ("GetCrosshair off=" + [OSDSidekick.DDC]::GetCrosshair($mh, 0))
} catch { Write-Output "Set ERR: $($_.Exception.Message)" }
# Also RTK_HUB from 32-bit
try {
  [void][OSDSidekick.RTK_HUB]::DLL_init()
  $mhR = [Activator]::CreateInstance([OSDSidekick.RTK_HUB].GetNestedType("Monitor_Handle"))
  $mhR.Realtek = $h
  Write-Output ("RTK GetCrosshair=" + [OSDSidekick.RTK_HUB]::GetCrosshair($mhR))
  [OSDSidekick.RTK_HUB]::SetCrosshair1ON($mhR)
  Start-Sleep -Milliseconds 800
  Write-Output ("RTK after ON=" + [OSDSidekick.RTK_HUB]::GetCrosshair($mhR))
  [OSDSidekick.RTK_HUB]::SetCrosshairOFF($mhR)
} catch { Write-Output "RTK ERR: $($_.Exception.Message)" }