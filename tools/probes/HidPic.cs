using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class HidPic
{
    public const int VendorId = 0x0BDA;
    public const int ProductId = 0x1100;
    public const ushort PropPicture = 0xE02C;

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
    static extern bool GetOverlappedResult(IntPtr h, ref OVERLAPPED ov, out int transferred, bool wait);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CancelIo(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateEvent(IntPtr a, bool m, bool i, string n);

    // Also VCP verify
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc cb, IntPtr data);
    delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szPhysicalMonitorDescription;
    }
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)]
    static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte code, out IntPtr typ, out uint cur, out uint max);

    static byte[] Build(ushort prop, ushort value, bool write)
    {
        byte[] buf = new byte[193];
        buf[0] = 0; buf[1] = 0x40; buf[2] = 0xc6;
        buf[7] = 0x20; buf[8] = 0; buf[9] = 0x6e; buf[10] = 0; buf[11] = 0x80;
        var msg = new List<byte>();
        msg.Add((byte)(prop >> 8)); msg.Add((byte)prop);
        msg.Add((byte)(value >> 8)); msg.Add((byte)value);
        byte op = write ? (byte)0x03 : (byte)0x01;
        byte[] pre = { 0x51, (byte)(0x81 + msg.Count), op };
        int off = 1 + 0x40;
        Array.Copy(pre, 0, buf, off, pre.Length);
        for (int i = 0; i < msg.Count; i++) buf[off + pre.Length + i] = msg[i];
        return buf;
    }

    static IntPtr Open()
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
                    if (HidD_GetAttributes(h, ref attr) && attr.VendorID == VendorId && attr.ProductID == ProductId) return h;
                    CloseHandle(h);
                }
                finally { Marshal.FreeHGlobal(detail); }
            }
        }
        finally { SetupDiDestroyDeviceInfoList(info); }
        throw new Exception("HID not found");
    }

    static bool Send(IntPtr h, byte[] packet)
    {
        if (HidD_SetOutputReport(h, packet, packet.Length)) return true;
        var ov = new OVERLAPPED();
        ov.hEvent = CreateEvent(IntPtr.Zero, true, false, null);
        try
        {
            int written;
            bool ok = WriteFile(h, packet, packet.Length, out written, ref ov);
            int err = Marshal.GetLastWin32Error();
            if (!ok && err != 997) return false;
            if (ok) return written > 0;
            if (WaitForSingleObject(ov.hEvent, 800) != 0) { CancelIo(h); return false; }
            return GetOverlappedResult(h, ref ov, out written, false) && written > 0;
        }
        finally { if (ov.hEvent != IntPtr.Zero) CloseHandle(ov.hEvent); }
    }

    static string ReadVcp14()
    {
        string result = "n/a";
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, hdc, lprc, data) =>
        {
            uint count = 0;
            GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
            if (count == 0) return true;
            var arr = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) return true;
            try
            {
                IntPtr typ; uint cur = 0, max = 0;
                bool ok = GetVCPFeatureAndVCPFeatureReply(arr[0].hPhysicalMonitor, 0x14, out typ, out cur, out max);
                result = "ok=" + ok + " cur=" + cur + " max=" + max;
            }
            finally { DestroyPhysicalMonitors(count, arr); }
            return false;
        }, IntPtr.Zero);
        return result;
    }

    public static int Run()
    {
        Console.WriteLine("VCP14 before: " + ReadVcp14());
        IntPtr h = Open();
        try
        {
            foreach (ushort v in new ushort[] { 0, 1, 2, 3, 4, 5, 6, 7 })
            {
                bool ok = Send(h, Build(PropPicture, v, true));
                Thread.Sleep(250);
                Console.WriteLine("HID set E02C=" + v + " writeOk=" + ok + " VCP14=" + ReadVcp14());
            }
            // restore to 7 via HID
            Send(h, Build(PropPicture, 7, true));
            Thread.Sleep(200);
            Console.WriteLine("restore VCP14=" + ReadVcp14());
        }
        finally { CloseHandle(h); }
        return 0;
    }
}
