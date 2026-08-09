#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# 1) Try SetMonitorBrightness (Windows dxva2 / DDC)
# 2) Try SET_SDR_WHITE_LEVEL (Windows DisplayConfig, HDR SDR content brightness)

$type = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class BrightSetProbe {
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
  public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string szPhysicalMonitorDescription;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct MONITORINFOEX {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public uint dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string szDevice;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int left, top, right, bottom; }

  [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint min, ref uint cur, ref uint max);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint newBrightness);

  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] public struct HEADER { public int type; public int size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator; public uint Denominator; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET {
    public LUID adapterId; public uint id; public uint modeInfoIdx; public int outputTechnology; public int rotation; public int scaling;
    public RATIONAL refreshRate; public int scanLineOrdering; public bool targetAvailable; public uint statusFlags;
  }
  [StructLayout(LayoutKind.Sequential)] public struct PATH { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE { public int infoType; public uint id; public LUID adapterId; public ulong p0,p1,p2,p3,p4,p5,p6; }
  [StructLayout(LayoutKind.Sequential)] public struct SDR_GET { public HEADER header; public uint SDRWhiteLevel; }
  [StructLayout(LayoutKind.Sequential)] public struct SDR_SET { public HEADER header; public uint SDRWhiteLevel; public byte finalValue; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct TARGET_NAME {
    public HEADER header; public uint flags; public int outputTechnology;
    public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string monitorDevicePath;
  }

  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH[] paths, ref uint modeCount, [Out] MODE[] modes, IntPtr topology);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref TARGET_NAME packet);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SDR_GET packet);
  [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SDR_SET packet);

  public static void TestDdc() {
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) => {
      var mi = new MONITORINFOEX();
      mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
      GetMonitorInfo(hMon, ref mi);
      uint count = 0;
      GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
      if (count == 0) return true;
      var arr = new PHYSICAL_MONITOR[count];
      if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) return true;
      try {
        uint min=0, cur=0, max=0;
        bool got = GetMonitorBrightness(arr[0].hPhysicalMonitor, ref min, ref cur, ref max);
        Console.WriteLine("DDC GET device=" + mi.szDevice + " ok=" + got + " min=" + min + " cur=" + cur + " max=" + max);
        if (!got) return true;

        uint original = cur;
        uint target = cur >= max ? (min + 1) : (cur + 1);
        if (target > max) target = max;
        bool setOk = SetMonitorBrightness(arr[0].hPhysicalMonitor, target);
        int err = Marshal.GetLastWin32Error();
        System.Threading.Thread.Sleep(400);
        uint min2=0, cur2=0, max2=0;
        GetMonitorBrightness(arr[0].hPhysicalMonitor, ref min2, ref cur2, ref max2);
        Console.WriteLine("DDC SET to=" + target + " setOk=" + setOk + " err=" + err + " readback=" + cur2);

        // restore
        SetMonitorBrightness(arr[0].hPhysicalMonitor, original);
        System.Threading.Thread.Sleep(200);
        GetMonitorBrightness(arr[0].hPhysicalMonitor, ref min2, ref cur2, ref max2);
        Console.WriteLine("DDC restored to=" + original + " readback=" + cur2);
      } finally {
        DestroyPhysicalMonitors(count, arr);
      }
      return true;
    }, IntPtr.Zero);
  }

  public static void TestSdrNits() {
    uint pc, mc;
    GetDisplayConfigBufferSizes(2, out pc, out mc);
    var paths = new PATH[pc];
    var modes = new MODE[mc];
    QueryDisplayConfig(2, ref pc, paths, ref mc, modes, IntPtr.Zero);
    for (int i = 0; i < pc; i++) {
      var n = new TARGET_NAME();
      n.header.type = 2; n.header.size = Marshal.SizeOf(typeof(TARGET_NAME));
      n.header.adapterId = paths[i].targetInfo.adapterId; n.header.id = paths[i].targetInfo.id;
      DisplayConfigGetDeviceInfo(ref n);

      var g = new SDR_GET();
      g.header.type = 11; g.header.size = Marshal.SizeOf(typeof(SDR_GET));
      g.header.adapterId = paths[i].targetInfo.adapterId; g.header.id = paths[i].targetInfo.id;
      int gr = DisplayConfigGetDeviceInfo(ref g);
      double nits = g.SDRWhiteLevel * 80.0 / 1000.0;
      Console.WriteLine("SDR GET name=" + n.monitorFriendlyDeviceName + " result=" + gr + " raw=" + g.SDRWhiteLevel + " nits=" + nits.ToString("0.0"));

      uint original = g.SDRWhiteLevel;
      // bump by ~10 nits => delta raw = 10*1000/80 = 125
      uint bumped = original + 125;
      var s = new SDR_SET();
      s.header.type = unchecked((int)0xFFFFFFEE); // SET_SDR_WHITE_LEVEL
      s.header.size = Marshal.SizeOf(typeof(SDR_SET));
      s.header.adapterId = paths[i].targetInfo.adapterId;
      s.header.id = paths[i].targetInfo.id;
      s.SDRWhiteLevel = bumped;
      s.finalValue = 1;
      int sr = DisplayConfigSetDeviceInfo(ref s);
      System.Threading.Thread.Sleep(300);
      DisplayConfigGetDeviceInfo(ref g);
      Console.WriteLine("SDR SET bumped raw=" + bumped + " setResult=" + sr + " readbackRaw=" + g.SDRWhiteLevel + " nits=" + (g.SDRWhiteLevel * 80.0 / 1000.0).ToString("0.0"));

      // restore
      s.SDRWhiteLevel = original;
      DisplayConfigSetDeviceInfo(ref s);
      System.Threading.Thread.Sleep(200);
      DisplayConfigGetDeviceInfo(ref g);
      Console.WriteLine("SDR restored raw=" + original + " readback=" + g.SDRWhiteLevel);
    }
  }
}
"@

Add-Type -TypeDefinition $type -Language CSharp
Write-Output "=== DDC brightness set/get ==="
[BrightSetProbe]::TestDdc()
Write-Output "=== SDR white level set/get ==="
[BrightSetProbe]::TestSdrNits()
