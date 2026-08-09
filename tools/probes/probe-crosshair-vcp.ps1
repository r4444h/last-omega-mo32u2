Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class VcpProbe {
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
  public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string szPhysicalMonitorDescription;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public struct MONITORINFOEX {
    public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szDevice;
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte bVCPCode, out IntPtr pvct, out uint pdwCurrentValue, out uint pdwMaximumValue);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

  public static void Run() {
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) => {
      var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
      GetMonitorInfo(hMon, ref mi);
      uint count=0; GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
      if (count==0) return true;
      var arr = new PHYSICAL_MONITOR[count];
      if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) return true;
      try {
        IntPtr typ; uint cur=0, max=0;
        bool ok = GetVCPFeatureAndVCPFeatureReply(arr[0].hPhysicalMonitor, 0x37, out typ, out cur, out max);
        int err = Marshal.GetLastWin32Error();
        Console.WriteLine("Device=" + mi.szDevice + " phys=" + arr[0].szPhysicalMonitorDescription + " VCP37 getOk=" + ok + " cur=" + cur + " max=" + max + " err=" + err);

        // Also try a few related codes
        foreach (byte code in new byte[]{0x36,0x37,0xE0,0xE1,0xE2}) {
          ok = GetVCPFeatureAndVCPFeatureReply(arr[0].hPhysicalMonitor, code, out typ, out cur, out max);
          err = Marshal.GetLastWin32Error();
          Console.WriteLine("  VCP 0x" + code.ToString("X2") + " ok=" + ok + " cur=" + cur + " max=" + max + " err=" + err);
        }
      } finally { DestroyPhysicalMonitors(count, arr); }
      return true;
    }, IntPtr.Zero);
  }
}
"@
[VcpProbe]::Run()
