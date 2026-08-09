$sidekick = "C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick"
Set-Location $sidekick
$env:PATH = "$sidekick;" + $env:PATH
[Environment]::CurrentDirectory = $sidekick
Add-Type -Path "D:\Projects\mirabox\last-omega\scripts\RtkProbe2.cs"
[RtkProbe2]::Run()
