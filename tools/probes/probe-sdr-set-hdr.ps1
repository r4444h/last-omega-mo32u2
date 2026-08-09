Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SdrSet2 {
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
  // Packed like native: header(20) + uint + byte + padding to 4
  [StructLayout(LayoutKind.Sequential, Pack = 1)]
  public struct SDR_SET_P1 { public HEADER header; public uint SDRWhiteLevel; public byte finalValue; }
  [StructLayout(LayoutKind.Sequential)]
  public struct SDR_SET_DEF { public HEADER header; public uint SDRWhiteLevel; public byte finalValue; public byte p1,p2,p3; }

  [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);
  [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] PATH[] paths, ref uint modeCount, [Out] MODE[] modes, IntPtr topology);
  [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SDR_GET packet);
  [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SDR_SET_P1 packet);
  [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SDR_SET_DEF packet);

  public static void Run() {
    Console.WriteLine("sizeof P1=" + Marshal.SizeOf(typeof(SDR_SET_P1)) + " DEF=" + Marshal.SizeOf(typeof(SDR_SET_DEF)) + " GET=" + Marshal.SizeOf(typeof(SDR_GET)) + " HEADER=" + Marshal.SizeOf(typeof(HEADER)));
    uint pc, mc; GetDisplayConfigBufferSizes(2, out pc, out mc);
    var paths = new PATH[pc]; var modes = new MODE[mc];
    QueryDisplayConfig(2, ref pc, paths, ref mc, modes, IntPtr.Zero);
    var adapter = paths[0].targetInfo.adapterId; var id = paths[0].targetInfo.id;

    var g = new SDR_GET();
    g.header.type = 11; g.header.size = Marshal.SizeOf(typeof(SDR_GET));
    g.header.adapterId = adapter; g.header.id = id;
    DisplayConfigGetDeviceInfo(ref g);
    Console.WriteLine("HDR-ON GET raw=" + g.SDRWhiteLevel + " nits=" + (g.SDRWhiteLevel*80.0/1000.0));

    uint orig = g.SDRWhiteLevel;
    uint bumped = orig + 250; // +20 nits

    var s1 = new SDR_SET_P1();
    s1.header.type = unchecked((int)0xFFFFFFEE);
    s1.header.size = Marshal.SizeOf(typeof(SDR_SET_P1));
    s1.header.adapterId = adapter; s1.header.id = id;
    s1.SDRWhiteLevel = bumped; s1.finalValue = 1;
    int r1 = DisplayConfigSetDeviceInfo(ref s1);
    System.Threading.Thread.Sleep(300);
    DisplayConfigGetDeviceInfo(ref g);
    Console.WriteLine("SET Pack1 result=" + r1 + " readback=" + g.SDRWhiteLevel);

    var s2 = new SDR_SET_DEF();
    s2.header.type = unchecked((int)0xFFFFFFEE);
    s2.header.size = Marshal.SizeOf(typeof(SDR_SET_DEF));
    s2.header.adapterId = adapter; s2.header.id = id;
    s2.SDRWhiteLevel = bumped; s2.finalValue = 1;
    int r2 = DisplayConfigSetDeviceInfo(ref s2);
    System.Threading.Thread.Sleep(300);
    DisplayConfigGetDeviceInfo(ref g);
    Console.WriteLine("SET DefPad result=" + r2 + " readback=" + g.SDRWhiteLevel);

    // restore via def
    s2.SDRWhiteLevel = orig;
    DisplayConfigSetDeviceInfo(ref s2);
  }
}
"@
[SdrSet2]::Run()
