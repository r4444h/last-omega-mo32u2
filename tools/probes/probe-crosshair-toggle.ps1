$ErrorActionPreference = "Stop"
$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
[Environment]::CurrentDirectory = $sidekick
Set-Location $sidekick
$env:PATH = "$sidekick;$env:PATH"
Add-Type -Path "$sidekick\OSDSidekick.dll"

[void][OSDSidekick.DDC]::DLL_init()
[void][OSDSidekick.RTK_HUB]::DLL_init()

$vendorId = [uint16]0x0BDA
$productId = [uint16]0x1100
$count = [OSDSidekick.DDC]::RTK_Get_MultiHID($vendorId, $productId)
Write-Output "RTK_Get_MultiHID=$count"
if ($count -le 0) { throw "No Realtek HID found" }

$dev = [OSDSidekick.DDC]::RTK_Open_mutiHID(0)
Write-Output "RTK_Open_mutiHID(0)=$dev"

$mhType = [OSDSidekick.DDC].GetNestedType("Monitor_Handle")
$mh = [Activator]::CreateInstance($mhType)
$mh.index = 0
$mh.Realtek = $dev
$mh.Genesys = 0
$mh.VIA = [IntPtr]::Zero
$mh.MTK = [IntPtr]::Zero
$mh.MS_Handle = [IntPtr]::Zero

# Also RTK_HUB handle type
$mhR = [Activator]::CreateInstance([OSDSidekick.RTK_HUB].GetNestedType("Monitor_Handle"))
$mhR.index = 0
$mhR.Realtek = $dev
$mhR.Genesys = 0
$mhR.VIA = [IntPtr]::Zero
$mhR.MTK = [IntPtr]::Zero
$mhR.MS_Handle = [IntPtr]::Zero

$model = New-Object byte[] 64
[OSDSidekick.DDC]::GetSocModel_Realtek($mh, $model)
$modelStr = [Text.Encoding]::ASCII.GetString($model).Trim([char]0)
Write-Output "SocModel_Realtek='$modelStr'"

$pidBuf = New-Object byte[] 64
[OSDSidekick.DDC]::GetSocProductID_Realtek($mh, $pidBuf)
$pidStr = [Text.Encoding]::ASCII.GetString($pidBuf).Trim([char]0)
Write-Output "SocProductID_Realtek='$pidStr'"

# Get crosshair via DDC (ddctype?) and RTK_HUB
foreach ($ddctype in 0,1,2,3,4,5) {
  try {
    $g = [OSDSidekick.DDC]::GetCrosshair($mh, $ddctype)
    Write-Output "DDC.GetCrosshair ddctype=$ddctype => $g"
  } catch { Write-Output "DDC.GetCrosshair ddctype=$ddctype ERR $($_.Exception.Message)" }
}
try {
  $g2 = [OSDSidekick.RTK_HUB]::GetCrosshair($mhR)
  Write-Output "RTK_HUB.GetCrosshair => $g2"
} catch { Write-Output "RTK_HUB.GetCrosshair ERR $($_.Exception.Message)" }

# Toggle: ON style 1 then OFF - user can visually verify; we restore OFF after
Write-Output "SetCrosshair1ON via RTK_HUB..."
[OSDSidekick.RTK_HUB]::SetCrosshair1ON($mhR)
Start-Sleep -Milliseconds 800
$afterOn = [OSDSidekick.RTK_HUB]::GetCrosshair($mhR)
Write-Output "after ON GetCrosshair=$afterOn"
Write-Output "SetCrosshairOFF..."
[OSDSidekick.RTK_HUB]::SetCrosshairOFF($mhR)
Start-Sleep -Milliseconds 500
$afterOff = [OSDSidekick.RTK_HUB]::GetCrosshair($mhR)
Write-Output "after OFF GetCrosshair=$afterOff"

# Also try DDC methods with ddctype 0
Write-Output "DDC SetCrosshair1ON ddctype=0"
[OSDSidekick.DDC]::SetCrosshair1ON($mh, 0)
Start-Sleep -Milliseconds 800
Write-Output "DDC GetCrosshair=$([OSDSidekick.DDC]::GetCrosshair($mh, 0))"
[OSDSidekick.DDC]::SetCrosshairOFF($mh, 0)
Write-Output "DDC after OFF=$([OSDSidekick.DDC]::GetCrosshair($mh, 0))"
Write-Output "DONE"
