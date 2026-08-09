$ErrorActionPreference = "Stop"
$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
[Environment]::CurrentDirectory = $sidekick
Set-Location $sidekick

# Resolve native deps from same folder
$env:PATH = "$sidekick;$env:PATH"

Add-Type -Path "$sidekick\OSDSidekick.dll"

Write-Output "==== Types with Monitor_Handle ===="
$asm = [OSDSidekick.DDC].Assembly
$asm.GetTypes() | Where-Object { $_.Name -match 'Monitor|Handle|All_|Windows' } | ForEach-Object {
  Write-Output "TYPE $($_.FullName)"
  $_.GetConstructors() | ForEach-Object {
    $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
    Write-Output "  ctor($ps)"
  }
  $_.GetFields([Reflection.BindingFlags]'Public,NonPublic,Instance,Static,DeclaredOnly') | ForEach-Object {
    Write-Output "  field $($_.FieldType.Name) $($_.Name)"
  }
  $_.GetProperties([Reflection.BindingFlags]'Public,NonPublic,Instance,Static,DeclaredOnly') | Select-Object -First 30 | ForEach-Object {
    Write-Output "  prop $($_.PropertyType.Name) $($_.Name)"
  }
  $_.GetMethods([Reflection.BindingFlags]'Public,Static,DeclaredOnly') | Select-Object -First 40 | ForEach-Object {
    $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
    Write-Output "  static $($_.ReturnType.Name) $($_.Name)($ps)"
  }
}

Write-Output "==== DDC static methods Init/Get ===="
[OSDSidekick.DDC].GetMethods([Reflection.BindingFlags]'Public,Static') | ForEach-Object {
  $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
  Write-Output "  $($_.ReturnType.Name) $($_.Name)($ps)"
} | Select-Object -First 80

Write-Output "==== RTK_HUB methods ===="
[OSDSidekick.RTK_HUB].GetMethods([Reflection.BindingFlags]'Public,Static') | ForEach-Object {
  $ps = ($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
  Write-Output "  $($_.ReturnType.Name) $($_.Name)($ps)"
}

Write-Output "==== Try DLL_init ===="
$ok = [OSDSidekick.DDC]::DLL_init()
Write-Output "DDC.DLL_init=$ok"
$ok2 = [OSDSidekick.RTK_HUB]::DLL_init()
Write-Output "RTK_HUB.DLL_init=$ok2"
$lib = [OSDSidekick.DDC]::dllexp_LibInitial()
Write-Output "dllexp_LibInitial=$lib"
