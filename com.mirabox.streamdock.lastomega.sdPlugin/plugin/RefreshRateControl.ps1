#Requires -Version 5.1
<#
.SYNOPSIS
  Read current display refresh rate (Hz) via DisplayConfig.

.EXAMPLE
  .\RefreshRateControl.ps1 -Action status -NameFilter MO32U2
  .\RefreshRateControl.ps1 -Action list
#>
[CmdletBinding()]
param(
  [ValidateSet('list', 'status')]
  [string]$Action = 'status',

  [string]$NameFilter = 'MO32U2',

  [switch]$Primary
)

$ErrorActionPreference = 'Stop'

$cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class RefreshRateNative {
  public const int QDC_ONLY_ACTIVE_PATHS = 2;
  public const int ERROR_SUCCESS = 0;
  public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;

  [StructLayout(LayoutKind.Sequential)]
  public struct LUID { public uint LowPart; public int HighPart; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
    public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_PATH_TARGET_INFO {
    public LUID adapterId; public uint id; public uint modeInfoIdx;
    public int outputTechnology; public int rotation; public int scaling;
    public DISPLAYCONFIG_RATIONAL refreshRate; public int scanLineOrdering;
    public bool targetAvailable; public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_PATH_INFO {
    public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
    public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
    public uint flags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct POINTL { public int x; public int y; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_SOURCE_MODE {
    public uint width; public uint height; public int pixelFormat; public POINTL position;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_2DREGION { public uint cx; public uint cy; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO {
    public ulong pixelRate;
    public DISPLAYCONFIG_RATIONAL hSyncFreq;
    public DISPLAYCONFIG_RATIONAL vSyncFreq;
    public DISPLAYCONFIG_2DREGION activeSize;
    public DISPLAYCONFIG_2DREGION totalSize;
    public uint videoStandard;
    public int scanLineOrdering;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_TARGET_MODE {
    public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int left, top, right, bottom; }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO {
    public POINTL PathSourceSize; public RECT DesktopImageRegion; public RECT DesktopImageClip;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct DISPLAYCONFIG_MODE_INFO {
    [FieldOffset(0)] public int infoType;
    [FieldOffset(4)] public uint id;
    [FieldOffset(8)] public LUID adapterId;
    [FieldOffset(16)] public DISPLAYCONFIG_TARGET_MODE targetMode;
    [FieldOffset(16)] public DISPLAYCONFIG_SOURCE_MODE sourceMode;
    [FieldOffset(16)] public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
    public int type; public int size; public LUID adapterId; public uint id;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public uint flags;
    public int outputTechnology;
    public ushort edidManufactureId;
    public ushort edidProductCodeId;
    public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
  }

  [DllImport("user32.dll")]
  public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

  [DllImport("user32.dll")]
  public static extern int QueryDisplayConfig(
    uint flags, ref uint numPathArrayElements, [Out] DISPLAYCONFIG_PATH_INFO[] pathArray,
    ref uint numModeInfoArrayElements, [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

  [DllImport("user32.dll")]
  public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

  public class DisplayHz {
    public string Name;
    public string Path;
    public bool IsPrimary;
    public int Width;
    public int Height;
    public double Hz;
    public int HzRounded;
  }

  static double RationalHz(DISPLAYCONFIG_RATIONAL r) {
    if (r.Denominator == 0) return 0;
    return (double)r.Numerator / (double)r.Denominator;
  }

  static int NiceHz(double hz) {
    if (hz <= 0 || double.IsNaN(hz) || double.IsInfinity(hz)) return 0;

    // Snap to common panel rates (OS often reports 239.76 / 143.9 / 59.94).
    int[] commons = {
      24, 25, 30, 48, 50, 60, 72, 75, 90, 100, 120, 144, 165, 180, 200, 240, 360
    };
    int best = 0;
    double bestDist = double.MaxValue;
    foreach (int c in commons) {
      double d = Math.Abs(hz - c);
      if (d < bestDist) { bestDist = d; best = c; }
    }
    if (bestDist <= 1.5) return best;

    // Otherwise: fractional → round up; whole number → as-is.
    double floor = Math.Floor(hz);
    if (hz - floor > 0.001) return (int)Math.Ceiling(hz);
    return (int)floor;
  }

  public static List<DisplayHz> GetDisplays() {
    var result = new List<DisplayHz>();
    uint pathCount, modeCount;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != ERROR_SUCCESS)
      return result;

    var paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
    var modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != ERROR_SUCCESS)
      return result;

    for (int i = 0; i < pathCount; i++) {
      var path = paths[i];
      var namePacket = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
      namePacket.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
      namePacket.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
      namePacket.header.adapterId = path.targetInfo.adapterId;
      namePacket.header.id = path.targetInfo.id;
      DisplayConfigGetDeviceInfo(ref namePacket);

      double hz = RationalHz(path.targetInfo.refreshRate);
      int width = 0, height = 0;
      bool primary = false;

      uint srcIdx = path.sourceInfo.modeInfoIdx;
      if (srcIdx != 0xFFFFFFFFu && srcIdx < modeCount && modes[srcIdx].infoType == 1) {
        width = (int)modes[srcIdx].sourceMode.width;
        height = (int)modes[srcIdx].sourceMode.height;
        primary = modes[srcIdx].sourceMode.position.x == 0 && modes[srcIdx].sourceMode.position.y == 0;
      }

      uint tgtIdx = path.targetInfo.modeInfoIdx;
      if ((hz <= 0 || double.IsNaN(hz)) && tgtIdx != 0xFFFFFFFFu && tgtIdx < modeCount && modes[tgtIdx].infoType == 2) {
        hz = RationalHz(modes[tgtIdx].targetMode.targetVideoSignalInfo.vSyncFreq);
      }

      result.Add(new DisplayHz {
        Name = namePacket.monitorFriendlyDeviceName ?? "",
        Path = namePacket.monitorDevicePath ?? "",
        IsPrimary = primary,
        Width = width,
        Height = height,
        Hz = hz,
        HzRounded = NiceHz(hz)
      });
    }
    return result;
  }
}
'@

if (-not ('RefreshRateNative' -as [type])) {
  Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction Stop | Out-Null
}

function Convert-Display($d) {
  [ordered]@{
    name      = [string]$d.Name
    path      = [string]$d.Path
    isPrimary = [bool]$d.IsPrimary
    width     = [int]$d.Width
    height    = [int]$d.Height
    hz        = [math]::Round([double]$d.Hz, 3)
    hzRounded = [int]$d.HzRounded
    label     = if ($d.HzRounded -gt 0) { "$($d.HzRounded)Hz" } else { '—Hz' }
  }
}

function Select-Target($filter, $preferPrimary) {
  $all = [RefreshRateNative]::GetDisplays()
  if (-not $all -or $all.Count -eq 0) { throw 'No active displays found.' }

  $candidates = $all
  if ($filter) {
    $candidates = @($all | Where-Object { $_.Name -like "*$filter*" -or $_.Path -like "*$filter*" })
  }
  if (-not $candidates -or $candidates.Count -eq 0) {
    throw "No display matched filter '$filter'."
  }
  if ($preferPrimary -or $candidates.Count -gt 1) {
    $primary = @($candidates | Where-Object { $_.IsPrimary }) | Select-Object -First 1
    if ($primary) { return $primary }
  }
  return $candidates[0]
}

try {
  switch ($Action) {
    'list' {
      $displays = @([RefreshRateNative]::GetDisplays() | ForEach-Object { Convert-Display $_ })
      [ordered]@{ ok = $true; displays = $displays } | ConvertTo-Json -Compress -Depth 5
    }
    'status' {
      $d = Select-Target -filter $NameFilter -preferPrimary:([bool]$Primary -or [string]::IsNullOrWhiteSpace($NameFilter))
      $disp = Convert-Display $d
      [ordered]@{ ok = $true; display = $disp } | ConvertTo-Json -Compress -Depth 5
    }
  }
} catch {
  $msg = $_.Exception.Message -replace '[\\\"\r\n]', ' '
  Write-Output ("{`"ok`":false,`"error`":`"$msg`"}")
  exit 1
}
