#Requires -Version 5.1
<#
.SYNOPSIS
  Read/adjust monitor brightness via Windows APIs:
  - SDR: dxva2 SetMonitorBrightness (DDC)
  - HDR: DisplayConfig SET_SDR_WHITE_LEVEL (SDR content brightness)

.EXAMPLE
  .\BrightnessControl.ps1 -Action status -NameFilter MO32U2
  .\BrightnessControl.ps1 -Action adjust -NameFilter MO32U2 -Delta 2
  .\BrightnessControl.ps1 -Action set -NameFilter MO32U2 -Value 40
#>
[CmdletBinding()]
param(
  [ValidateSet("list", "status", "adjust", "set")]
  [string]$Action = "status",
  [string]$NameFilter = "",
  [switch]$Primary,
  [int]$Delta = 0,
  [double]$Value = -1,
  [int]$StepSdr = 1,
  [int]$StepHdr = 10
)

$ErrorActionPreference = "Stop"

$typeDef = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class BrightNative
{
    public const int QDC_ONLY_ACTIVE_PATHS = 2;
    public const int ERROR_SUCCESS = 0;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO = 9;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL = 11;
    public const int DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2 = 15;
    public const int DISPLAYCONFIG_DEVICE_INFO_SET_SDR_WHITE_LEVEL = unchecked((int)0xFFFFFFEE);
    public const int DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR = 2;
    public const double MinSdrNits = 80.0;
    public const double MaxSdrNits = 480.0;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct HEADER { public int type; public int size; public LUID adapterId; public uint id; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_TARGET
    {
        public LUID adapterId; public uint id; public uint modeInfoIdx;
        public int outputTechnology; public int rotation; public int scaling;
        public RATIONAL refreshRate; public int scanLineOrdering;
        public bool targetAvailable; public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_MODE
    {
        public uint width; public uint height; public int pixelFormat; public POINTL position;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TARGET_MODE
    {
        public ulong pixelRate;
        public RATIONAL hSyncFreq; public RATIONAL vSyncFreq;
        public uint activeCx; public uint activeCy; public uint totalCx; public uint totalCy;
        public uint videoStandard; public int scanLineOrdering;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct MODE
    {
        [FieldOffset(0)] public int infoType;
        [FieldOffset(4)] public uint id;
        [FieldOffset(8)] public LUID adapterId;
        [FieldOffset(16)] public TARGET_MODE targetMode;
        [FieldOffset(16)] public SOURCE_MODE sourceMode;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct TARGET_NAME
    {
        public HEADER header;
        public uint flags;
        public int outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SOURCE_NAME
    {
        public HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ADV_COLOR
    {
        public HEADER header;
        public uint value;
        public int colorEncoding;
        public uint bitsPerColorChannel;
        public bool AdvancedColorSupported { get { return (value & 0x1) != 0; } }
        public bool AdvancedColorEnabled { get { return (value & 0x2) != 0; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ADV_COLOR2
    {
        public HEADER header;
        public uint value;
        public int colorEncoding;
        public uint bitsPerColorChannel;
        public int activeColorMode;
        public bool HighDynamicRangeSupported { get { return (value & (1u << 4)) != 0; } }
        public bool HighDynamicRangeUserEnabled { get { return (value & (1u << 5)) != 0; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SDR_GET
    {
        public HEADER header;
        public uint SDRWhiteLevel;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SDR_SET
    {
        public HEADER header;
        public uint SDRWhiteLevel;
        public byte finalValue;
        public byte pad1, pad2, pad3;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szPhysicalMonitorDescription;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int left, top, right, bottom; }

    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH[] paths, ref uint modeCount, [Out] MODE[] modes, IntPtr topology);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME packet);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME packet);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref ADV_COLOR packet);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref ADV_COLOR2 packet);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SDR_GET packet);
    [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SDR_SET packet);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);
    [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);
    [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)] public static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint min, ref uint current, ref uint max);
    [DllImport("dxva2.dll", SetLastError = true)] public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint newBrightness);

    public class DisplayBrightInfo
    {
        public string Name;
        public string Path;
        public string GdiDevice;
        public uint TargetId;
        public long AdapterLow;
        public int AdapterHigh;
        public bool IsPrimary;
        public bool HdrSupported;
        public bool HdrEnabled;
        public string Mode;
        public int? BrightnessPercent;
        public double? SdrWhiteNits;
        public string Label;
        public string Unit;
        public double Value;
    }

    private static bool WithPhysicalMonitor(string gdiDevice, Func<IntPtr, bool> fn)
    {
        bool done = false;
        bool ok = false;
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) =>
        {
            if (done) return true;
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (!GetMonitorInfo(hMon, ref mi) || !string.Equals(mi.szDevice, gdiDevice, StringComparison.OrdinalIgnoreCase))
                return true;

            uint count = 0;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count) || count == 0)
                return true;

            var arr = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr))
                return true;

            try
            {
                ok = fn(arr[0].hPhysicalMonitor);
                done = true;
            }
            finally
            {
                DestroyPhysicalMonitors(count, arr);
            }
            return true;
        }, IntPtr.Zero);
        return ok;
    }

    private static Dictionary<string, int> ReadDdcBrightnessByGdiDevice()
    {
        var map = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            if (!GetMonitorInfo(hMon, ref mi) || string.IsNullOrEmpty(mi.szDevice))
                return true;

            uint count = 0;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count) || count == 0)
                return true;

            var arr = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr))
                return true;

            try
            {
                uint min = 0, cur = 0, max = 0;
                if (GetMonitorBrightness(arr[0].hPhysicalMonitor, ref min, ref cur, ref max))
                {
                    int pct = max > min ? (int)Math.Round(100.0 * (cur - min) / (max - min)) : (int)cur;
                    if (pct < 0) pct = 0;
                    if (pct > 100) pct = 100;
                    map[mi.szDevice] = pct;
                }
            }
            finally
            {
                DestroyPhysicalMonitors(count, arr);
            }
            return true;
        }, IntPtr.Zero);
        return map;
    }

    private static void FillLabel(DisplayBrightInfo info)
    {
        if (info.HdrEnabled && info.SdrWhiteNits.HasValue)
        {
            info.Value = Math.Round(info.SdrWhiteNits.Value);
            info.Unit = "nits";
            info.Label = ((int)info.Value).ToString() + "n";
        }
        else if (info.BrightnessPercent.HasValue)
        {
            info.Value = info.BrightnessPercent.Value;
            info.Unit = "percent";
            info.Label = info.BrightnessPercent.Value.ToString() + "%";
        }
        else if (info.SdrWhiteNits.HasValue)
        {
            info.Value = Math.Round(info.SdrWhiteNits.Value);
            info.Unit = "nits";
            info.Label = ((int)info.Value).ToString() + "n";
        }
        else
        {
            info.Value = 0;
            info.Unit = "unknown";
            info.Label = "N/A";
        }
    }

    public static List<DisplayBrightInfo> GetDisplays()
    {
        var result = new List<DisplayBrightInfo>();
        var ddc = ReadDdcBrightnessByGdiDevice();

        uint pathCount, modeCount;
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != ERROR_SUCCESS)
            return result;

        var paths = new PATH[pathCount];
        var modes = new MODE[modeCount];
        if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != ERROR_SUCCESS)
            return result;

        for (int i = 0; i < pathCount; i++)
        {
            var path = paths[i];
            var adapterId = path.targetInfo.adapterId;
            var targetId = path.targetInfo.id;

            var targetName = new TARGET_NAME();
            targetName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            targetName.header.size = Marshal.SizeOf(typeof(TARGET_NAME));
            targetName.header.adapterId = adapterId;
            targetName.header.id = targetId;
            DisplayConfigGetDeviceInfo(ref targetName);

            var sourceName = new SOURCE_NAME();
            sourceName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            sourceName.header.size = Marshal.SizeOf(typeof(SOURCE_NAME));
            sourceName.header.adapterId = path.sourceInfo.adapterId;
            sourceName.header.id = path.sourceInfo.id;
            DisplayConfigGetDeviceInfo(ref sourceName);

            bool hdrSupported = false;
            bool hdrEnabled = false;
            string mode = "SDR";

            var info2 = new ADV_COLOR2();
            info2.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2;
            info2.header.size = Marshal.SizeOf(typeof(ADV_COLOR2));
            info2.header.adapterId = adapterId;
            info2.header.id = targetId;
            if (DisplayConfigGetDeviceInfo(ref info2) == ERROR_SUCCESS)
            {
                hdrSupported = info2.HighDynamicRangeSupported;
                hdrEnabled = info2.activeColorMode == DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR
                             || info2.HighDynamicRangeUserEnabled;
                mode = hdrEnabled ? "HDR" : (info2.activeColorMode == 1 ? "WCG" : "SDR");
            }
            else
            {
                var info = new ADV_COLOR();
                info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
                info.header.size = Marshal.SizeOf(typeof(ADV_COLOR));
                info.header.adapterId = adapterId;
                info.header.id = targetId;
                if (DisplayConfigGetDeviceInfo(ref info) == ERROR_SUCCESS)
                {
                    hdrSupported = info.AdvancedColorSupported;
                    hdrEnabled = info.AdvancedColorEnabled;
                    mode = hdrEnabled ? "HDR" : "SDR";
                }
            }

            double? sdrNits = null;
            var sdr = new SDR_GET();
            sdr.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL;
            sdr.header.size = Marshal.SizeOf(typeof(SDR_GET));
            sdr.header.adapterId = adapterId;
            sdr.header.id = targetId;
            if (DisplayConfigGetDeviceInfo(ref sdr) == ERROR_SUCCESS && sdr.SDRWhiteLevel > 0)
                sdrNits = sdr.SDRWhiteLevel * 80.0 / 1000.0;

            int? brightness = null;
            if (!string.IsNullOrEmpty(sourceName.viewGdiDeviceName) && ddc.ContainsKey(sourceName.viewGdiDeviceName))
                brightness = ddc[sourceName.viewGdiDeviceName];

            int x = 0, y = 0;
            bool isPrimary = false;
            uint srcIdx = path.sourceInfo.modeInfoIdx;
            if (srcIdx != 0xFFFFFFFFu && srcIdx < modeCount && modes[srcIdx].infoType == 1)
            {
                x = modes[srcIdx].sourceMode.position.x;
                y = modes[srcIdx].sourceMode.position.y;
                isPrimary = (x == 0 && y == 0);
            }

            var item = new DisplayBrightInfo
            {
                Name = targetName.monitorFriendlyDeviceName ?? "",
                Path = targetName.monitorDevicePath ?? "",
                GdiDevice = sourceName.viewGdiDeviceName ?? "",
                TargetId = targetId,
                AdapterLow = adapterId.LowPart,
                AdapterHigh = adapterId.HighPart,
                IsPrimary = isPrimary,
                HdrSupported = hdrSupported,
                HdrEnabled = hdrEnabled,
                Mode = mode,
                BrightnessPercent = brightness,
                SdrWhiteNits = sdrNits
            };
            FillLabel(item);
            result.Add(item);
        }

        return result;
    }

    public static bool SetDdcBrightnessPercent(DisplayBrightInfo display, int percent)
    {
        if (string.IsNullOrEmpty(display.GdiDevice)) return false;
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;

        return WithPhysicalMonitor(display.GdiDevice, hPhys =>
        {
            uint min = 0, cur = 0, max = 0;
            if (!GetMonitorBrightness(hPhys, ref min, ref cur, ref max))
                return false;
            uint raw = max > min
                ? (uint)Math.Round(min + (max - min) * (percent / 100.0))
                : (uint)percent;
            if (raw < min) raw = min;
            if (raw > max) raw = max;
            return SetMonitorBrightness(hPhys, raw);
        });
    }

    public static bool SetSdrWhiteNits(DisplayBrightInfo display, double nits)
    {
        // Soft absolute limits; plugin JS applies user HDR min/max.
        if (nits < 1.0) nits = 1.0;
        if (nits > 10000.0) nits = 10000.0;

        var adapter = new LUID { LowPart = (uint)display.AdapterLow, HighPart = display.AdapterHigh };
        var packet = new SDR_SET();
        packet.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_SDR_WHITE_LEVEL;
        packet.header.size = Marshal.SizeOf(typeof(SDR_SET));
        packet.header.adapterId = adapter;
        packet.header.id = display.TargetId;
        packet.SDRWhiteLevel = (uint)Math.Round(nits * 1000.0 / 80.0);
        packet.finalValue = 1;
        return DisplayConfigSetDeviceInfo(ref packet) == ERROR_SUCCESS;
    }

    public static bool SetValue(DisplayBrightInfo display, double value)
    {
        if (display.HdrEnabled)
            return SetSdrWhiteNits(display, value);
        // DDC brightness is integer percent 0..100
        int pct = (int)Math.Round(value);
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return SetDdcBrightnessPercent(display, pct);
    }
}
"@

if (-not ("BrightNative" -as [type])) {
  Add-Type -TypeDefinition $typeDef -Language CSharp
}

function Convert-Display([BrightNative+DisplayBrightInfo]$d) {
  [pscustomobject]@{
    name               = $d.Name
    path               = $d.Path
    gdiDevice          = $d.GdiDevice
    isPrimary          = [bool]$d.IsPrimary
    hdrSupported       = [bool]$d.HdrSupported
    hdrEnabled         = [bool]$d.HdrEnabled
    mode               = $d.Mode
    brightnessPercent  = $d.BrightnessPercent
    sdrWhiteNits       = $d.SdrWhiteNits
    label              = $d.Label
    unit               = $d.Unit
    value              = $d.Value
  }
}

function Select-TargetDisplay {
  param([string]$Filter, [bool]$PreferPrimary)

  $all = [BrightNative]::GetDisplays()
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
      throw "No display matched filter '$Filter'."
    }
  }
  elseif ($PreferPrimary) {
    $primary = @($all | Where-Object { $_.IsPrimary })
    if ($primary.Count -gt 0) { $candidates = $primary }
  }

  return $candidates[0]
}

switch ($Action) {
  "list" {
    $all = [BrightNative]::GetDisplays()
    @{
      ok       = $true
      action   = "list"
      displays = @($all | ForEach-Object { Convert-Display $_ })
    } | ConvertTo-Json -Compress -Depth 5
  }
  "status" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    @{
      ok      = $true
      action  = "status"
      display = Convert-Display $target
    } | ConvertTo-Json -Compress -Depth 5
  }
  "adjust" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    $ok = [BrightNative]::Adjust($target, $Delta, $StepSdr, $StepHdr)
    Start-Sleep -Milliseconds 150
    $after = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    @{
      ok      = [bool]$ok
      action  = "adjust"
      delta   = $Delta
      stepSdr = $StepSdr
      stepHdr = $StepHdr
      display = Convert-Display $after
    } | ConvertTo-Json -Compress -Depth 5
  }
  "set" {
    $target = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    if ($Value -lt 0) { throw "Value is required for -Action set" }
    $ok = [BrightNative]::SetValue($target, $Value)
    Start-Sleep -Milliseconds 150
    $after = Select-TargetDisplay -Filter $NameFilter -PreferPrimary:$Primary.IsPresent
    @{
      ok      = [bool]$ok
      action  = "set"
      value   = $Value
      display = Convert-Display $after
    } | ConvertTo-Json -Compress -Depth 5
  }
}
