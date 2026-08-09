$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class VcpPicSet {
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);
  public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string szPhysicalMonitorDescription;
  }
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte bVCPCode, out IntPtr pvct, out uint pdwCurrentValue, out uint pdwMaximumValue);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

  static IntPtr hPhys = IntPtr.Zero;
  static PHYSICAL_MONITOR[] arr;
  static uint count;

  public static bool Init() {
    bool found = false;
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) => {
      if (found) return true;
      count=0; GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
      if (count==0) return true;
      arr = new PHYSICAL_MONITOR[count];
      if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) return true;
      hPhys = arr[0].hPhysicalMonitor;
      found = true;
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static void Close() {
    if (arr != null) DestroyPhysicalMonitors(count, arr);
  }

  public static string Get(byte code) {
    IntPtr typ; uint cur=0, max=0;
    bool ok = GetVCPFeatureAndVCPFeatureReply(hPhys, code, out typ, out cur, out max);
    return "ok="+ok+" cur="+cur+" max="+max;
  }

  public static string Set(byte code, uint val) {
    bool ok = SetVCPFeature(hPhys, code, val);
    System.Threading.Thread.Sleep(120);
    return "setOk="+ok+" " + Get(code);
  }
}
"@

if (-not [VcpPicSet]::Init()) { throw 'no monitor' }
try {
  Write-Output ("before 14: " + [VcpPicSet]::Get(0x14))
  Write-Output ("before E0: " + [VcpPicSet]::Get(0xE0))
  $orig = 7
  # briefly set a few values and restore
  foreach ($v in 0,1,2,3,4,5,6,7,8,9,10,11) {
    Write-Output ("SET 0x14=$v => " + [VcpPicSet]::Set(0x14, [uint32]$v))
  }
  Write-Output ("restore => " + [VcpPicSet]::Set(0x14, [uint32]$orig))
} finally {
  [VcpPicSet]::Close()
}
