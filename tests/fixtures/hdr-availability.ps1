$ErrorActionPreference = 'Stop'
# Replace the native boundary with counters. No monitor or Windows API is called.
Add-Type -TypeDefinition @'
using System;
public static class BrightNative {
  public static int Writes;
  public class DisplayBrightInfo {
    public string Name="MO32U2", Path="test", GdiDevice="test", Mode="HDR", Label="HDR OSD", Unit="unavailable";
    public bool IsPrimary=true, HdrSupported=true, HdrEnabled=true, ControlAvailable=false;
    public int? BrightnessPercent=null;
    public double? SdrWhiteNits=210;
    public double Value;
    public string UnavailableReason="Use monitor OSD for HDR brightness";
  }
  public static DisplayBrightInfo[] GetDisplays(){ return new[]{new DisplayBrightInfo()}; }
  public static bool SetValue(DisplayBrightInfo display,double value){ Writes++; return true; }
}
public static class GbPictureMode {
  public static int Writes, Reads;
  public static int GetVcp(){Reads++;return 7;}
  public static string SetBoth(int value){Writes++;return "{}";}
}
'@
$taskPlugin = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'com.mirabox.streamdock.lastomega.sdPlugin\plugin'
$taskChecks = [ordered]@{}
foreach($taskAction in @('status','set','adjust')) {
  $taskRaw = & (Join-Path $taskPlugin 'BrightnessControl.ps1') -Action $taskAction -NameFilter MO32U2 -Value 50 -Delta 1
  $taskChecks['brightness_'+$taskAction] = ($taskRaw | Out-String).Trim() | ConvertFrom-Json
}
foreach($taskAction in @('status','list','set','delta','default')) {
  $taskRaw = & (Join-Path $taskPlugin 'PictureModeControl.ps1') -Action $taskAction -KnownHdrEnabled $true -Value 0 -Delta 1
  $taskChecks['picture_'+$taskAction] = ($taskRaw | Out-String).Trim() | ConvertFrom-Json
}
$taskChecks.counters = @{ brightnessWrites=[BrightNative]::Writes;pictureWrites=[GbPictureMode]::Writes;pictureReads=[GbPictureMode]::Reads }
$taskChecks | ConvertTo-Json -Compress -Depth 8
exit 0
