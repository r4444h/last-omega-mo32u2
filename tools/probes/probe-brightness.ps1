#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$brightType = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class BrightProbe {
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
  public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string szPhysicalMonitorDescription;
  }

  [DllImport("dxva2.dll", SetLastError = true)]
  public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint pdwNumberOfPhysicalMonitors);

  [DllImport("dxva2.dll", SetLastError = true)]
  public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

  [DllImport("dxva2.dll", SetLastError = true)]
  public static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, [In] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

  [DllImport("dxva2.dll", SetLastError = true)]
  public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint pdwMinimumBrightness, ref uint pdwCurrentBrightness, ref uint pdwMaximumBrightness);

  [DllImport("user32.dll", CharSet = CharSet.Auto)]
  public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

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

  public static List<string> Probe() {
    var lines = new List<string>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) => {
      var mi = new MONITORINFOEX();
      mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
      GetMonitorInfo(hMon, ref mi);
      uint count = 0;
      GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
      lines.Add("Device=" + mi.szDevice + " physicalCount=" + count);
      if (count > 0) {
        var arr = new PHYSICAL_MONITOR[count];
        if (GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) {
          for (int i = 0; i < arr.Length; i++) {
            uint minB = 0, curB = 0, maxB = 0;
            bool ok = GetMonitorBrightness(arr[i].hPhysicalMonitor, ref minB, ref curB, ref maxB);
            int err = Marshal.GetLastWin32Error();
            lines.Add("  phys=" + arr[i].szPhysicalMonitorDescription + " brightnessOk=" + ok + " min=" + minB + " cur=" + curB + " max=" + maxB + " err=" + err);
          }
          DestroyPhysicalMonitors(count, arr);
        }
      }
      return true;
    }, IntPtr.Zero);
    return lines;
  }
}
"@

Add-Type -TypeDefinition $brightType -Language CSharp
[BrightProbe]::Probe() | ForEach-Object { $_ }

$sdrType = @"
using System;
using System.Runtime.InteropServices;

public static class SdrProbe {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] public struct HEADER { public int type; public int size; public LUID adapterId; public uint id; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_SOURCE { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)] public struct RATIONAL { public uint Numerator; public uint Denominator; }
  [StructLayout(LayoutKind.Sequential)] public struct PATH_TARGET {
    public LUID adapterId; public uint id; public uint modeInfoIdx; public int outputTechnology; public int rotation; public int scaling;
    public RATIONAL refreshRate; public int scanLineOrdering; public bool targetAvailable; public uint statusFlags;
  }
  [StructLayout(LayoutKind.Sequential)] public struct PATH { public PATH_SOURCE sourceInfo; public PATH_TARGET targetInfo; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] public struct MODE {
    public int infoType; public uint id; public LUID adapterId;
    public ulong pad0, pad1, pad2, pad3, pad4, pad5, pad6;
  }
  [StructLayout(LayoutKind.Sequential)] public struct SDR { public HEADER header; public uint SDRWhiteLevel; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct NAME {
    public HEADER header; public uint flags; public int outputTechnology;
    public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
  }

  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH[] paths, ref uint modeCount, [Out] MODE[] modes, IntPtr topology);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref NAME packet);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SDR packet);

  public static void Run() {
    uint pc, mc;
    GetDisplayConfigBufferSizes(2, out pc, out mc);
    var paths = new PATH[pc];
    var modes = new MODE[mc];
    QueryDisplayConfig(2, ref pc, paths, ref mc, modes, IntPtr.Zero);
    for (int i = 0; i < pc; i++) {
      var n = new NAME();
      n.header.type = 2;
      n.header.size = Marshal.SizeOf(typeof(NAME));
      n.header.adapterId = paths[i].targetInfo.adapterId;
      n.header.id = paths[i].targetInfo.id;
      DisplayConfigGetDeviceInfo(ref n);

      var s = new SDR();
      s.header.type = 11; // GET_SDR_WHITE_LEVEL
      s.header.size = Marshal.SizeOf(typeof(SDR));
      s.header.adapterId = paths[i].targetInfo.adapterId;
      s.header.id = paths[i].targetInfo.id;
      int r = DisplayConfigGetDeviceInfo(ref s);
      double nits = s.SDRWhiteLevel * 80.0 / 1000.0;
      Console.WriteLine(n.monitorFriendlyDeviceName + " getSdrResult=" + r + " raw=" + s.SDRWhiteLevel + " nits=" + nits.ToString("0.0"));
    }
  }
}
"@

Add-Type -TypeDefinition $sdrType -Language CSharp
Write-Output "==== SDR white level ===="
[SdrProbe]::Run()
