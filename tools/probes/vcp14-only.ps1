Add-Type @"
using System; using System.Runtime.InteropServices;
public static class V {
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr a,IntPtr b,MonitorEnumProc c,IntPtr d);
  public delegate bool MonitorEnumProc(IntPtr h,IntPtr a,IntPtr b,IntPtr c);
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Auto)] public struct PHYSICAL_MONITOR { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string n; }
  [DllImport("dxva2.dll",SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, ref uint c);
  [DllImport("dxva2.dll",SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint c, [Out] PHYSICAL_MONITOR[] m);
  [DllImport("dxva2.dll",SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint c, [In] PHYSICAL_MONITOR[] m);
  [DllImport("dxva2.dll",SetLastError=true)] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out IntPtr t, out uint cur, out uint max);
  public static void Run(){
    EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,(h,a,b,c)=>{
      uint n=0; GetNumberOfPhysicalMonitorsFromHMONITOR(h,ref n); if(n==0) return true;
      var m=new PHYSICAL_MONITOR[n]; if(!GetPhysicalMonitorsFromHMONITOR(h,n,m)) return true;
      try{ IntPtr t; uint cur,max; bool ok=GetVCPFeatureAndVCPFeatureReply(m[0].h,0x14,out t,out cur,out max); Console.WriteLine("VCP14 ok="+ok+" cur="+cur+" max="+max);
           ok=GetVCPFeatureAndVCPFeatureReply(m[0].h,0xE0,out t,out cur,out max); Console.WriteLine("VCPE0 ok="+ok+" cur="+cur+" max="+max);
      } finally{ DestroyPhysicalMonitors(n,m);} return true;
    },IntPtr.Zero);
  }
}
"@
[V]::Run()