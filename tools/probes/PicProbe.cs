using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PicProbe {
  public const int VendorId = 0x0BDA;
  public const int ProductId = 0x1100;
  public const ushort PropPicture = 0xE02C;

  private const uint DIGCF_PRESENT = 2, DIGCF_DEVICEINTERFACE = 0x10;
  private const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
  private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3, FILE_ATTRIBUTE_NORMAL = 0x80;
  private static readonly IntPtr INVALID = new IntPtr(-1);

  [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
  [StructLayout(LayoutKind.Sequential)] struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber; }

  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
  [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_SetOutputReport(IntPtr h, byte[] b, int n);
  [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetInputReport(IntPtr h, byte[] b, int n);
  [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid c, IntPtr e, IntPtr w, uint f);
  [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid c, uint i, ref SP_DEVICE_INTERFACE_DATA a);
  [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA a, IntPtr detail, int sz, out int req, IntPtr info);
  [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] static extern IntPtr CreateFile(string n, uint a, uint sh, IntPtr sec, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(IntPtr h, byte[] b, int n, out int r, IntPtr ov);

  static byte[] Build(ushort prop, ushort value, bool write) {
    byte[] buf = new byte[193];
    buf[0]=0; buf[1]=0x40; buf[2]=0xc6; buf[7]=0x20; buf[8]=0; buf[9]=0x6e; buf[10]=0; buf[11]=0x80;
    var msg = new List<byte>();
    if (prop > 0xff) { msg.Add((byte)(prop>>8)); msg.Add((byte)prop); } else msg.Add((byte)prop);
    msg.Add((byte)(value>>8)); msg.Add((byte)value);
    byte op = write ? (byte)0x03 : (byte)0x01;
    byte[] pre = new byte[]{0x51,(byte)(0x81+msg.Count),op};
    int off = 1+0x40;
    Array.Copy(pre,0,buf,off,pre.Length);
    for (int i=0;i<msg.Count;i++) buf[off+pre.Length+i]=msg[i];
    return buf;
  }

  static IntPtr Open() {
    Guid g; HidD_GetHidGuid(out g);
    IntPtr info = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT|DIGCF_DEVICEINTERFACE);
    try {
      for (uint i=0;;i++) {
        var ifd = new SP_DEVICE_INTERFACE_DATA(); ifd.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
        if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref g, i, ref ifd)) break;
        int req; SetupDiGetDeviceInterfaceDetail(info, ref ifd, IntPtr.Zero, 0, out req, IntPtr.Zero);
        IntPtr detail = Marshal.AllocHGlobal(req);
        try {
          Marshal.WriteInt32(detail, IntPtr.Size==8 ? 8 : 4+Marshal.SystemDefaultCharSize);
          if (!SetupDiGetDeviceInterfaceDetail(info, ref ifd, detail, req, out req, IntPtr.Zero)) continue;
          string path = Marshal.PtrToStringAuto(new IntPtr(detail.ToInt64()+4));
          IntPtr h = CreateFile(path, GENERIC_READ|GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
          if (h==INVALID) continue;
          var attr = new HIDD_ATTRIBUTES(); attr.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
          if (HidD_GetAttributes(h, ref attr) && attr.VendorID==VendorId && attr.ProductID==ProductId) return h;
          CloseHandle(h);
        } finally { Marshal.FreeHGlobal(detail); }
      }
    } finally { SetupDiDestroyDeviceInfoList(info); }
    throw new Exception("device not found");
  }

  static bool Send(IntPtr h, byte[] p) {
    if (HidD_SetOutputReport(h, p, p.Length)) return true;
    int w; return WriteFile(h, p, p.Length, out w, IntPtr.Zero) && w>0;
  }

  static string Hex(byte[] b, int n) {
    var sb=new StringBuilder();
    for(int i=0;i<n;i++){ if(i>0)sb.Append(' '); sb.Append(b[i].ToString("X2")); }
    return sb.ToString();
  }

  static int ParseVal(byte[] resp) {
    for (int i=0;i<resp.Length-4;i++) {
      if (resp[i]==0xE0 && resp[i+1]==0x2C) return (resp[i+2]<<8)|resp[i+3];
    }
    // common reply layouts
    int idx = 1+0x40+3;
    if (idx+1 < resp.Length) return (resp[idx]<<8)|resp[idx+1];
    return -1;
  }

  public static void Run() {
    IntPtr h = Open();
    try {
      // READ current
      byte[] req = Build(PropPicture, 0, false);
      Console.WriteLine("send read ok=" + Send(h, req));
      System.Threading.Thread.Sleep(60);
      byte[] resp = new byte[193];
      int r=0;
      bool ok = HidD_GetInputReport(h, resp, resp.Length);
      if (!ok) ReadFile(h, resp, resp.Length, out r, IntPtr.Zero);
      Console.WriteLine("read ok="+ok+" bytes="+r+" sample="+Hex(resp, 80));
      Console.WriteLine("parsed=" + ParseVal(resp));

      // Try reading brightness too for sanity (0x10)
      req = Build(0x10, 0, false);
      Send(h, req);
      System.Threading.Thread.Sleep(60);
      Array.Clear(resp,0,resp.Length);
      ok = HidD_GetInputReport(h, resp, resp.Length);
      Console.WriteLine("bright read sample="+Hex(resp, 80)+" parsed10="+ParseValGeneric(resp,0x10));
    } finally { CloseHandle(h); }
  }

  static int ParseValGeneric(byte[] resp, int prop) {
    byte hi=(byte)((prop>>8)&0xff), lo=(byte)(prop&0xff);
    for (int i=0;i<resp.Length-4;i++) {
      if ((prop>0xff && resp[i]==hi && resp[i+1]==lo) || (prop<=0xff && resp[i]==lo)) {
        if (prop>0xff) return (resp[i+2]<<8)|resp[i+3];
        return (resp[i+1]<<8)|resp[i+2];
      }
    }
    return -1;
  }
}