using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class RtkCross
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
    public static extern void GetSocModel_Realtek(Monitor_Handle m_handle, byte[] str);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetCrosshair(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshair1ON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshair2ON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshair3ON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshair4ON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetCrosshairOFF(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetBrightness(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetContrast(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern ushort GetAIM(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetAIMON(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void SetAIMOFF(Monitor_Handle m_handle);

    // Alternate layouts / calling conventions to probe.
    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.StdCall, EntryPoint = "GetCrosshair")]
    public static extern ushort GetCrosshairStd(Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "GetCrosshair")]
    public static extern ushort GetCrosshairRef(ref Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "SetCrosshair1ON")]
    public static extern void SetCrosshair1ONRef(ref Monitor_Handle m_handle);

    [DllImport("RTKCmd_x64.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "GetBrightness")]
    public static extern ushort GetBrightnessRef(ref Monitor_Handle m_handle);

    public static int Run(string mode)
    {
        Console.WriteLine("DLL_init=" + DLL_init());
        int n = RTK_Get_MultiHID(0x0BDA, 0x1100);
        Console.WriteLine("MultiHID=" + n);
        if (n <= 0) return 2;

        int h = RTK_Open_mutiHID(0);
        Console.WriteLine("Open0=" + h);

        var mh = new Monitor_Handle();
        mh.Realtek = (mode == "index") ? 0 : h;
        mh.index = 0;

        byte[] model = new byte[64];
        GetSocModel_Realtek(mh, model);
        Console.WriteLine("Model=" + Encoding.ASCII.GetString(model).Trim('\0') + " RealtekField=" + mh.Realtek);

        if (mode == "ref")
        {
            Console.WriteLine("BrightRef=" + GetBrightnessRef(ref mh) + " CrossRef=" + GetCrosshairRef(ref mh));
            Console.WriteLine("SetCrosshair1ONRef...");
            SetCrosshair1ONRef(ref mh);
            Thread.Sleep(1000);
            Console.WriteLine("CrossAfterOnRef=" + GetCrosshairRef(ref mh));
            SetCrosshairOFF(mh);
            Thread.Sleep(400);
            Console.WriteLine("CrossAfterOff=" + GetCrosshairRef(ref mh));
            return 0;
        }

        Console.WriteLine(
            "Bright=" + GetBrightness(mh) +
            " Contrast=" + GetContrast(mh) +
            " Cross=" + GetCrosshair(mh) +
            " AIM=" + GetAIM(mh) +
            " CrossStd=" + GetCrosshairStd(mh));

        Console.WriteLine("SetCrosshair1ON...");
        SetCrosshair1ON(mh);
        Thread.Sleep(1000);
        Console.WriteLine("CrossAfterOn=" + GetCrosshair(mh));
        SetCrosshairOFF(mh);
        Thread.Sleep(400);
        Console.WriteLine("CrossAfterOff=" + GetCrosshair(mh));
        return 0;
    }
}
