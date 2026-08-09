using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class HidPic2
{
    public const ushort Prop = 0xE02C;
    private const uint DIGCF_PRESENT = 2, DIGCF_DEVICEINTERFACE = 0x10;
    private const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    private const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x80, FILE_FLAG_OVERLAPPED = 0x40000000;
    private static readonly IntPtr INVALID = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber; }
    [StructLayout(LayoutKind.Sequential)]
    struct OVERLAPPED { public IntPtr Internal, InternalHigh; public int Offset, OffsetHigh; public IntPtr hEvent; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct PHYSICAL_MONITOR
    {
        public IntPtr h;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string n;
    }

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll", SetLastError = true)] static extern bool HidD_SetOutputReport(IntPtr h, byte[] b, int n);
    [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid c, IntPtr e, IntPtr w, uint f);
    [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid c, uint i, ref SP_DEVICE_INTERFACE_DATA a);
    [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA a, IntPtr detail, int sz, out int req, IntPtr info);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern IntPtr CreateFile(string n, uint a, uint sh, IntPtr sec, uint c, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, ref OVERLAPPED ov);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetOverlappedResult(IntPtr h, ref OVERLAPPED ov, out int x, bool wait);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CancelIo(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateEvent(IntPtr a, bool m, bool i, string n);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, MonitorEnumProc c, IntPtr d);
    public delegate bool MonitorEnumProc(IntPtr h, IntPtr a, IntPtr b, IntPtr c);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, ref uint c);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint c, [Out] PHYSICAL_MONITOR[] m);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool DestroyPhysicalMonitors(uint c, [In] PHYSICAL_MONITOR[] m);
    [DllImport("dxva2.dll", SetLastError = true)]
    static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out IntPtr t, out uint cur, out uint max);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);

    static byte[] Build(ushort prop, ushort value)
    {
        byte[] buf = new byte[193];
        buf[0] = 0; buf[1] = 0x40; buf[2] = 0xc6;
        buf[7] = 0x20; buf[8] = 0; buf[9] = 0x6e; buf[10] = 0; buf[11] = 0x80;
        byte[] msg = new byte[] { (byte)(prop >> 8), (byte)prop, (byte)(value >> 8), (byte)value };
        byte[] pre = new byte[] { 0x51, (byte)(0x81 + msg.Length), 0x03 };
        int off = 1 + 0x40;
        Array.Copy(pre, 0, buf, off, pre.Length);
        Array.Copy(msg, 0, buf, off + pre.Length, msg.Length);
        return buf;
    }

    static IntPtr OpenHid()
    {
        Guid g; HidD_GetHidGuid(out g);
        IntPtr info = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        try
        {
            for (uint i = 0; ; i++)
            {
                var ifd = new SP_DEVICE_INTERFACE_DATA();
                ifd.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref g, i, ref ifd)) break;
                int req; SetupDiGetDeviceInterfaceDetail(info, ref ifd, IntPtr.Zero, 0, out req, IntPtr.Zero);
                IntPtr detail = Marshal.AllocHGlobal(req);
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 4 + Marshal.SystemDefaultCharSize);
                    if (!SetupDiGetDeviceInterfaceDetail(info, ref ifd, detail, req, out req, IntPtr.Zero)) continue;
                    string path = Marshal.PtrToStringAuto(new IntPtr(detail.ToInt64() + 4));
                    IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                        IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED, IntPtr.Zero);
                    if (h == INVALID) continue;
                    var attr = new HIDD_ATTRIBUTES(); attr.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
                    if (HidD_GetAttributes(h, ref attr) && attr.VendorID == 0x0BDA && attr.ProductID == 0x1100) return h;
                    CloseHandle(h);
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(info); }
        throw new Exception("no hid");
    }

    static bool Send(IntPtr h, byte[] p)
    {
        if (HidD_SetOutputReport(h, p, p.Length)) return true;
        var ov = new OVERLAPPED();
        ov.hEvent = CreateEvent(IntPtr.Zero, true, false, null);
        try
        {
            int w; bool ok = WriteFile(h, p, p.Length, out w, ref ov);
            int err = Marshal.GetLastWin32Error();
            if (!ok && err != 997) return false;
            if (ok) return w > 0;
            if (WaitForSingleObject(ov.hEvent, 800) != 0) { CancelIo(h); return false; }
            return GetOverlappedResult(h, ref ov, out w, false) && w > 0;
        }
        finally { if (ov.hEvent != IntPtr.Zero) CloseHandle(ov.hEvent); }
    }

    static IntPtr phys;
    static PHYSICAL_MONITOR[] arr;
    static uint count;

    static bool InitVcp()
    {
        bool found = false;
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (h, a, b, c) =>
        {
            if (found) return true;
            count = 0;
            GetNumberOfPhysicalMonitorsFromHMONITOR(h, ref count);
            if (count == 0) return true;
            arr = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(h, count, arr)) return true;
            phys = arr[0].h;
            found = true;
            return true;
        }, IntPtr.Zero);
        return found;
    }

    static string Get14()
    {
        IntPtr t; uint cur, max;
        bool ok = GetVCPFeatureAndVCPFeatureReply(phys, 0x14, out t, out cur, out max);
        return ok ? ("cur=" + cur) : "fail";
    }

    public static void Run()
    {
        if (!InitVcp()) throw new Exception("no vcp");
        try
        {
            Console.WriteLine("start " + Get14());
            IntPtr hid = OpenHid();
            try
            {
                for (ushort v = 0; v <= 8; v++)
                {
                    bool wok = Send(hid, Build(Prop, v));
                    Thread.Sleep(450);
                    Console.WriteLine("HID " + v + " write=" + wok + " " + Get14());
                }
                for (uint v = 0; v <= 8; v++)
                {
                    bool sok = SetVCPFeature(phys, 0x14, v);
                    Thread.Sleep(450);
                    Console.WriteLine("VCP14 set " + v + " ok=" + sok + " " + Get14());
                }
                SetVCPFeature(phys, 0x14, 0);
                Thread.Sleep(200);
                Console.WriteLine("end " + Get14());
            }
            finally { CloseHandle(hid); }
        }
        finally { DestroyPhysicalMonitors(count, arr); }
    }
}
