$ErrorActionPreference = "Continue"
$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
[Environment]::CurrentDirectory = $sidekick
Set-Location $sidekick
$env:PATH = "$sidekick;$env:PATH"
Add-Type -Path "$sidekick\OSDSidekick.dll"

Write-Output "==== RTK_HUB DllImports Cross/Open/Init/GetBright ===="
[OSDSidekick.RTK_HUB].GetMethods([Reflection.BindingFlags]'Public,NonPublic,Static,DeclaredOnly') | ForEach-Object {
  $attrs = $_.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false)
  if ($attrs.Count -gt 0) {
    $a = $attrs[0]
    if ($_.Name -match 'Cross|AIM|Init|Open|Close|Bright|Multi|HID|GetSoc|Status|Number') {
      Write-Output "$($_.Name) -> $($a.Value) Entry=$($a.EntryPoint) CharSet=$($a.CharSet)"
    }
  }
}

Write-Output "==== DDC DllImports Cross/Open ===="
[OSDSidekick.DDC].GetMethods([Reflection.BindingFlags]'Public,NonPublic,Static,DeclaredOnly') | ForEach-Object {
  $attrs = $_.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute], $false)
  if ($attrs.Count -gt 0 -and $_.Name -match 'Cross|AIM|Init|Open|Multi|Realtek|RTK') {
    $a = $attrs[0]
    Write-Output "$($_.Name) -> $($a.Value) Entry=$($a.EntryPoint)"
  }
}

[void][OSDSidekick.RTK_HUB]::DLL_init()
[void][OSDSidekick.DDC]::DLL_init()
$vendorId = [uint16]0x0BDA
$productId = [uint16]0x1100
$count = [OSDSidekick.DDC]::RTK_Get_MultiHID($vendorId, $productId)
Write-Output "count=$count"

# Try opening all indices and probe brightness/crosshair
$mhType = [OSDSidekick.RTK_HUB].GetNestedType("Monitor_Handle")
for ($i=0; $i -lt 4; $i++) {
  $opened = [OSDSidekick.DDC]::RTK_Open_mutiHID($i)
  Write-Output "--- open index=$i handle=$opened ---"
  foreach ($dev in @($opened, $i, 0, 1)) {
    $mh = [Activator]::CreateInstance($mhType)
    $mh.Realtek = $dev
    try {
      $br = [OSDSidekick.RTK_HUB]::GetBrightness($mh)
      $cr = [OSDSidekick.RTK_HUB]::GetCrosshair($mh)
      $num = [OSDSidekick.RTK_HUB]::GetNumber($mh)
      Write-Output "  Realtek=$dev GetBrightness=$br GetCrosshair=$cr GetNumber=$num"
    } catch {
      Write-Output "  Realtek=$dev ERR $($_.Exception.Message)"
    }
  }
}

# List RTK_HUB get methods briefly
Write-Output "==== sample getters ===="
[OSDSidekick.RTK_HUB].GetMethods([Reflection.BindingFlags]'Public,Static') |
  Where-Object { $_.Name -match '^Get' -and $_.GetParameters().Count -eq 1 } |
  Select-Object -First 30 | ForEach-Object { Write-Output $_.Name }
