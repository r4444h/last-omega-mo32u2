using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class RtkProbe2
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Monitor_Handle
    {
        public int index;
        public IntPtr VIA;
        public IntPtr MTK;
        public int Realtek;
        public int Genesys;
        public IntPtr MS_Handle;
    }

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool DLL_init();

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int RTK_Get_MultiHID(ushort vendor_id, ushort product_id);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int RTK_Open_mutiHID(int mutiHIDindex);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void RTK_HID_Close(int realtek);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void GetSocModel_Realtek(Monitor_Handle m_handle, byte[] str);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetSocNum_RTK(int dev_realtek);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetBrightness(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetContrast(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetCrosshair(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetInput(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetHDR(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetBlackEQ(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetSharpness(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshair1ON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshairOFF(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool GetCurrent_Status_50(Monitor_Handle m_handle, byte[] ary);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool GetCurrent_Status_51(Monitor_Handle m_handle, byte[] ary);

    // Try as if API takes only int handle
    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "GetBrightness")]
    public static extern ushort GetBrightnessInt(int realtek);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "GetCrosshair")]
    public static extern ushort GetCrosshairInt(int realtek);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "SetCrosshair1ON")]
    public static extern void SetCrosshair1ONInt(int realtek);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "SetCrosshairOFF")]
    public static extern void SetCrosshairOFFInt(int realtek);

    static string Hex(byte[] b, int n)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.Append(b[i].ToString("X2")).Append(' ');
        return sb.ToString().Trim();
    }

    public static int Run()
    {
        Console.WriteLine("DLL_init=" + DLL_init());
        int n = RTK_Get_MultiHID(0x0BDA, 0x1100);
        Console.WriteLine("MultiHID=" + n);
        int h = RTK_Open_mutiHID(0);
        Console.WriteLine("Open0=" + h + " SocNum=" + GetSocNum_RTK(h));

        var mh = new Monitor_Handle { Realtek = h, index = 0 };
        byte[] model = new byte[64];
        GetSocModel_Realtek(mh, model);
        Console.WriteLine("Model=" + Encoding.ASCII.GetString(model).Trim('\0'));

        Console.WriteLine(
            "B=" + GetBrightness(mh) +
            " C=" + GetContrast(mh) +
            " X=" + GetCrosshair(mh) +
            " In=" + GetInput(mh) +
            " HDR=" + GetHDR(mh) +
            " BEQ=" + GetBlackEQ(mh) +
            " Sh=" + GetSharpness(mh));

        Console.WriteLine("Int API B=" + GetBrightnessInt(h) + " X=" + GetCrosshairInt(h));

        byte[] s50 = new byte[256];
        byte[] s51 = new byte[256];
        bool ok50 = GetCurrent_Status_50(mh, s50);
        bool ok51 = GetCurrent_Status_51(mh, s51);
        Console.WriteLine("Status50 ok=" + ok50 + " " + Hex(s50, 32));
        Console.WriteLine("Status51 ok=" + ok51 + " " + Hex(s51, 32));

        Console.WriteLine("Toggle Crosshair1 via struct...");
        SetCrosshair1ON(mh);
        Thread.Sleep(700);
        Console.WriteLine("X=" + GetCrosshair(mh));
        SetCrosshairOFF(mh);
        Thread.Sleep(400);
        Console.WriteLine("Xoff=" + GetCrosshair(mh));

        Console.WriteLine("Toggle Crosshair1 via int...");
        SetCrosshair1ONInt(h);
        Thread.Sleep(700);
        Console.WriteLine("Xint=" + GetCrosshairInt(h));
        SetCrosshairOFFInt(h);
        Thread.Sleep(400);
        Console.WriteLine("XintOff=" + GetCrosshairInt(h));

        return 0;
    }
}
