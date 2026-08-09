#Requires -Version 5.1
<#
.SYNOPSIS
  List / get / set / toggle Windows Display HDR via DisplayConfig APIs (Win11 24H2+).

.EXAMPLE
  .\HdrControl.ps1 -Action list
  .\HdrControl.ps1 -Action status -NameFilter MO32U2
  .\HdrControl.ps1 -Action toggle -NameFilter MO32U2
  .\HdrControl.ps1 -Action on -NameFilter MO32U2
  .\HdrControl.ps1 -Action off -NameFilter MO32U2
#>
[CmdletBinding()]
param(
  [ValidateSet("list", "status", "toggle", "on", "off")]
  [string]$Action = "list",

  # Match against friendly name or path (e.g. MO32U2, GBT, Gigabyte)
  [string]$NameFilter = "",

  # Prefer primary display when filter is empty / ambiguous
  [switch]$Primary
)

$ErrorActionPreference = "Stop"

$hdrTypeDef = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class HdrNative
{
    public const int QDC_ONLY_ACTIVE_PATHS = 2;
    public const int ERROR_SUCCESS = 0;

    public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO = 9;
    public const int DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE = 10;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2 = 15;
    public const int DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE = 16;

    public const int DISPLAYCONFIG_ADVANCED_COLOR_MODE_SDR = 0;
    public const int DISPLAYCONFIG_ADVANCED_COLOR_MODE_WCG = 1;
    public const int DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR = 2;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public int type;
        public int size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public int outputTechnology;
        public int rotation;
        public int scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public int scanLineOrdering;
        public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL
    {
        public uint Numerator;
        public uint Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_MODE
    {
        public uint width;
        public uint height;
        public int pixelFormat;
        public POINTL position;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_TARGET_MODE
    {
        public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
    {
        public ulong pixelRate;
        public DISPLAYCONFIG_RATIONAL hSyncFreq;
        public DISPLAYCONFIG_RATIONAL vSyncFreq;
        public DISPLAYCONFIG_2DREGION activeSize;
        public DISPLAYCONFIG_2DREGION totalSize;
        public uint videoStandard;
        public int scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_2DREGION
    {
        public uint cx;
        public uint cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO
    {
        public POINTL PathSourceSize;
        public RECT DesktopImageRegion;
        public RECT DesktopImageClip;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct DISPLAYCONFIG_MODE_INFO
    {
        [FieldOffset(0)] public int infoType;
        [FieldOffset(4)] public uint id;
        [FieldOffset(8)] public LUID adapterId;
        [FieldOffset(16)] public DISPLAYCONFIG_TARGET_MODE targetMode;
        [FieldOffset(16)] public DISPLAYCONFIG_SOURCE_MODE sourceMode;
        [FieldOffset(16)] public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAYCONFIG_TARGET_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint flags;
        public int outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string monitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint value;
        public int colorEncoding;
        public uint bitsPerColorChannel;

        public bool AdvancedColorSupported { get { return (value & 0x1) != 0; } }
        public bool AdvancedColorEnabled { get { return (value & 0x2) != 0; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint value;
        public int colorEncoding;
        public uint bitsPerColorChannel;
        public int activeColorMode;

        public bool HighDynamicRangeSupported { get { return (value & (1u << 4)) != 0; } }
        public bool HighDynamicRangeUserEnabled { get { return (value & (1u << 5)) != 0; } }
        public bool AdvancedColorSupported { get { return (value & 0x1) != 0; } }
        public bool AdvancedColorActive { get { return (value & 0x2) != 0; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SET_HDR_STATE
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint value;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint value;
    }

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(
        uint flags,
        ref uint numPathArrayElements,
        [Out] DISPLAYCONFIG_PATH_INFO[] pathArray,
        ref uint numModeInfoArrayElements,
        [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SET_HDR_STATE setPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE setPacket);

    public class DisplayInfo
    {
        public string Name;
        public string Path;
        public uint TargetId;
        public long AdapterLow;
        public int AdapterHigh;
        public bool HdrSupported;
        public bool HdrEnabled;
        public string Mode;
        public bool IsPrimary;
        public int X;
        public int Y;
    }

    private static string ModeName(int mode)
    {
        switch (mode)
        {
            case DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR: return "HDR";
            case DISPLAYCONFIG_ADVANCED_COLOR_MODE_WCG: return "WCG";
            default: return "SDR";
        }
    }

    public static List<DisplayInfo> GetDisplays()
    {
        var result = new List<DisplayInfo>();
        uint pathCount, modeCount;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != ERROR_SUCCESS)
            return result;

        var paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
        var modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != ERROR_SUCCESS)
            return result;

        for (int i = 0; i < pathCount; i++)
        {
            var path = paths[i];
            var targetId = path.targetInfo.id;
            var adapterId = path.targetInfo.adapterId;

            var namePacket = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            namePacket.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            namePacket.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            namePacket.header.adapterId = adapterId;
            namePacket.header.id = targetId;
            DisplayConfigGetDeviceInfo(ref namePacket);

            bool hdrSupported = false;
            bool hdrEnabled = false;
            string mode = "SDR";

            var info2 = new DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2();
            info2.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2;
            info2.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2));
            info2.header.adapterId = adapterId;
            info2.header.id = targetId;

            if (DisplayConfigGetDeviceInfo(ref info2) == ERROR_SUCCESS)
            {
                hdrSupported = info2.HighDynamicRangeSupported;
                hdrEnabled = info2.activeColorMode == DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR
                             || info2.HighDynamicRangeUserEnabled;
                mode = ModeName(info2.activeColorMode);
            }
            else
            {
                var info = new DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO();
                info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
                info.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO));
                info.header.adapterId = adapterId;
                info.header.id = targetId;
                if (DisplayConfigGetDeviceInfo(ref info) == ERROR_SUCCESS)
                {
                    hdrSupported = info.AdvancedColorSupported;
                    hdrEnabled = info.AdvancedColorEnabled;
                    mode = hdrEnabled ? "HDR" : "SDR";
                }
            }

            int x = 0, y = 0;
            bool isPrimary = false;
            uint srcIdx = path.sourceInfo.modeInfoIdx;
            // modeInfoIdx can be invalid (-1 as uint)
            if (srcIdx != 0xFFFFFFFFu && srcIdx < modeCount)
            {
                var srcMode = modes[srcIdx];
                // DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1
                if (srcMode.infoType == 1)
                {
                    x = srcMode.sourceMode.position.x;
                    y = srcMode.sourceMode.position.y;
                    isPrimary = (x == 0 && y == 0);
                }
            }

            result.Add(new DisplayInfo
            {
                Name = namePacket.monitorFriendlyDeviceName ?? "",
                Path = namePacket.monitorDevicePath ?? "",
                TargetId = targetId,
                AdapterLow = adapterId.LowPart,
                AdapterHigh = adapterId.HighPart,
                HdrSupported = hdrSupported,
                HdrEnabled = hdrEnabled,
                Mode = mode,
                IsPrimary = isPrimary,
                X = x,
                Y = y
            });
        }

        return result;
    }

    public static bool SetHdr(DisplayInfo display, bool enable)
    {
        var adapter = new LUID { LowPart = (uint)display.AdapterLow, HighPart = display.AdapterHigh };

        var setHdr = new DISPLAYCONFIG_SET_HDR_STATE();
        setHdr.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE;
        setHdr.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_SET_HDR_STATE));
        setHdr.header.adapterId = adapter;
        setHdr.header.id = display.TargetId;
        setHdr.value = enable ? 1u : 0u;

        if (DisplayConfigSetDeviceInfo(ref setHdr) == ERROR_SUCCESS)
            return true;

        var setAdv = new DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE();
        setAdv.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE;
        setAdv.header.size = Marshal.SizeOf(typeof(DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE));
        setAdv.header.adapterId = adapter;
        setAdv.header.id = display.TargetId;
        setAdv.value = enable ? 1u : 0u;
        return DisplayConfigSetDeviceInfo(ref setAdv) == ERROR_SUCCESS;
    }
}
"@

if (-not ("HdrNative" -as [type])) {
  Add-Type -TypeDefinition $hdrTypeDef -Language CSharp
}

function Convert-Display([HdrNative+DisplayInfo]$d) {
  [pscustomobject]@{
    name         = $d.Name
    path         = $d.Path
    hdrSupported = [bool]$d.HdrSupported
    hdrEnabled   = [bool]$d.HdrEnabled
    mode         = $d.Mode
    isPrimary    = [bool]$d.IsPrimary
    x            = $d.X
    y            = $d.Y
    targetId     = $d.TargetId
  }
}

function Select-TargetDisplay {
  param([string]$Filter, [bool]$PreferPrimary)

  $all = [HdrNative]::GetDisplays()
  if (-not $all -or $all.Count -eq 0) {
    throw "No active displays found."
  }

  $candidates = $all
  if ($Filter) {
    $candidates = @(
      $all | Where-Object {
        $_.Name -like "*$Filter*" -or $_.Path -like "*$Filter*"
      }
    )
    if ($candidates.Count -eq 0) {
      throw "No display matched filter '$Filter'. Available: $(($all | ForEach-Object { $_.Name }) -join ', ')"
    }
  }
  elseif ($PreferPrimary) {
    $primary = @($all | Where-Object { $_.IsPrimary })
    if ($primary.Count -gt 0) { $candidates = $primary }
  }

  # Prefer HDR-capable when multiple
  $hdrOnes = @($candidates | Where-Object { $_.HdrSupported })
  if ($hdrOnes.Count -gt 0) { $candidates = $hdrOnes }

  return $candidates[0]
}

$displays = [HdrNative]::GetDisplays()

switch ($Action) {
  "list" {
    $payload = @{
      ok       = $true
      action   = "list"
      displays = @($displays | ForEach-Object { Convert-Display $_ })
    }
    $payload | ConvertTo-Json -Compress -Depth 5
  }

  "status" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    $payload = @{
      ok      = $true
      action  = "status"
      display = Convert-Display $target
    }
    $payload | ConvertTo-Json -Compress -Depth 5
  }

  "toggle" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    if (-not $target.HdrSupported) {
      throw "Display '$($target.Name)' does not report HDR support."
    }
    $newState = -not $target.HdrEnabled
    $ok = [HdrNative]::SetHdr($target, $newState)
    Start-Sleep -Milliseconds 300
    $after = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    $payload = @{
      ok        = [bool]$ok
      action    = "toggle"
      requested = $newState
      display   = Convert-Display $after
    }
    $payload | ConvertTo-Json -Compress -Depth 5
  }

  "on" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    if (-not $target.HdrSupported) {
      throw "Display '$($target.Name)' does not report HDR support."
    }
    $ok = [HdrNative]::SetHdr($target, $true)
    Start-Sleep -Milliseconds 300
    $after = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    $payload = @{
      ok        = [bool]$ok
      action    = "on"
      requested = $true
      display   = Convert-Display $after
    }
    $payload | ConvertTo-Json -Compress -Depth 5
  }

  "off" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    if (-not $target.HdrSupported) {
      throw "Display '$($target.Name)' does not report HDR support."
    }
    $ok = [HdrNative]::SetHdr($target, $false)
    Start-Sleep -Milliseconds 300
    $after = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    $payload = @{
      ok        = [bool]$ok
      action    = "off"
      requested = $false
      display   = Convert-Display $after
    }
    $payload | ConvertTo-Json -Compress -Depth 5
  }
}
