param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('status', 'on', 'off', 'toggle', 'set')]
  [string]$Action,

  [ValidateRange(0, 4)]
  [int]$Style = 1,

  [int]$Value = -1
)

$ErrorActionPreference = 'Stop'
$StateFile = Join-Path $PSScriptRoot 'crosshair-state.json'

$cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public static class GbHidCrosshair {
  public const int VendorId = 0x0BDA;
  public const int ProductId = 0x1100;
  public const ushort PropCrosshair = 0xE037;

  private const uint DIGCF_PRESENT = 0x00000002;
  private const uint DIGCF_DEVICEINTERFACE = 0x00000010;
  private const uint GENERIC_READ = 0x80000000;
  private const uint GENERIC_WRITE = 0x40000000;
  private const uint FILE_SHARE_READ = 0x00000001;
  private const uint FILE_SHARE_WRITE = 0x00000002;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
  private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
  private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

  [StructLayout(LayoutKind.Sequential)]
  private struct SP_DEVICE_INTERFACE_DATA {
    public int cbSize;
    public Guid InterfaceClassGuid;
    public int Flags;
    public IntPtr Reserved;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct HIDD_ATTRIBUTES {
    public int Size;
    public ushort VendorID;
    public ushort ProductID;
    public ushort VersionNumber;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct OVERLAPPED {
    public IntPtr Internal;
    public IntPtr InternalHigh;
    public int Offset;
    public int OffsetHigh;
    public IntPtr hEvent;
  }

  [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid HidGuid);
  [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetAttributes(IntPtr HidDeviceObject, ref HIDD_ATTRIBUTES Attributes);
  [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_SetOutputReport(IntPtr HidDeviceObject, byte[] ReportBuffer, int ReportBufferLength);
  [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetInputReport(IntPtr HidDeviceObject, byte[] ReportBuffer, int ReportBufferLength);

  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, IntPtr Enumerator, IntPtr hwndParent, uint Flags);
  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, int DeviceInterfaceDetailDataSize, out int RequiredSize, IntPtr DeviceInfoData);
  [DllImport("setupapi.dll", SetLastError = true)]
  private static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

  [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr hObject);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool WriteFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToWrite, out int lpNumberOfBytesWritten, ref OVERLAPPED lpOverlapped);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool ReadFile(IntPtr hFile, byte[] lpBuffer, int nNumberOfBytesToRead, out int lpNumberOfBytesRead, ref OVERLAPPED lpOverlapped);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetOverlappedResult(IntPtr hFile, ref OVERLAPPED lpOverlapped, out int lpNumberOfBytesTransferred, bool bWait);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CancelIo(IntPtr hFile);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateEvent(IntPtr lpEventAttributes, bool bManualReset, bool bInitialState, string lpName);

  private static byte[] BuildPacket(ushort prop, ushort value, bool write) {
    byte[] buf = new byte[193];
    buf[0] = 0x00;
    buf[1] = 0x40;
    buf[2] = 0xc6;
    buf[1 + 6] = 0x20;
    buf[1 + 7] = 0x00;
    buf[1 + 8] = 0x6e;
    buf[1 + 9] = 0x00;
    buf[1 + 10] = 0x80;

    List<byte> msg = new List<byte>();
    if (prop > 0xff) {
      msg.Add((byte)((prop >> 8) & 0xff));
      msg.Add((byte)(prop & 0xff));
    } else {
      msg.Add((byte)(prop & 0xff));
    }
    msg.Add((byte)((value >> 8) & 0xff));
    msg.Add((byte)(value & 0xff));

    byte op = write ? (byte)0x03 : (byte)0x01;
    byte[] preamble = new byte[] { 0x51, (byte)(0x81 + msg.Count), op };
    int offset = 1 + 0x40;
    Array.Copy(preamble, 0, buf, offset, preamble.Length);
    for (int i = 0; i < msg.Count; i++) buf[offset + preamble.Length + i] = msg[i];
    return buf;
  }

  private static string[] FindDevicePaths() {
    Guid hidGuid;
    HidD_GetHidGuid(out hidGuid);
    IntPtr info = SetupDiGetClassDevs(ref hidGuid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (info == INVALID_HANDLE_VALUE) throw new Exception("SetupDiGetClassDevs failed: " + Marshal.GetLastWin32Error());

    List<string> paths = new List<string>();
    try {
      for (uint i = 0; ; i++) {
        SP_DEVICE_INTERFACE_DATA ifData = new SP_DEVICE_INTERFACE_DATA();
        ifData.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
        if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref hidGuid, i, ref ifData)) break;

        int required = 0;
        SetupDiGetDeviceInterfaceDetail(info, ref ifData, IntPtr.Zero, 0, out required, IntPtr.Zero);
        if (required <= 0) continue;

        IntPtr detailPtr = Marshal.AllocHGlobal(required);
        try {
          int detailSize = IntPtr.Size == 8 ? 8 : (4 + Marshal.SystemDefaultCharSize);
          Marshal.WriteInt32(detailPtr, detailSize);
          if (!SetupDiGetDeviceInterfaceDetail(info, ref ifData, detailPtr, required, out required, IntPtr.Zero)) continue;
          string path = Marshal.PtrToStringAuto(new IntPtr(detailPtr.ToInt64() + 4));
          if (string.IsNullOrEmpty(path)) continue;

          IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
          if (h == INVALID_HANDLE_VALUE) continue;
          try {
            HIDD_ATTRIBUTES attr = new HIDD_ATTRIBUTES();
            attr.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
            if (HidD_GetAttributes(h, ref attr) && attr.VendorID == VendorId && attr.ProductID == ProductId) {
              paths.Add(path);
            }
          } finally { CloseHandle(h); }
        } finally { Marshal.FreeHGlobal(detailPtr); }
      }
    } finally { SetupDiDestroyDeviceInfoList(info); }
    return paths.ToArray();
  }

  private static IntPtr OpenDevice(bool overlapped) {
    string[] paths = FindDevicePaths();
    if (paths.Length == 0) throw new Exception("Gigabyte Realtek HID 0BDA:1100 not found. Check monitor USB cable.");
    uint flags = FILE_ATTRIBUTE_NORMAL | (overlapped ? FILE_FLAG_OVERLAPPED : 0);
    foreach (string path in paths) {
      IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, flags, IntPtr.Zero);
      if (h != INVALID_HANDLE_VALUE) return h;
    }
    throw new Exception("Failed to open HID device: " + Marshal.GetLastWin32Error());
  }

  private static bool WaitIo(IntPtr h, ref OVERLAPPED ov, int timeoutMs, out int transferred) {
    transferred = 0;
    uint wr = WaitForSingleObject(ov.hEvent, (uint)timeoutMs);
    if (wr != 0) { // not WAIT_OBJECT_0
      CancelIo(h);
      return false;
    }
    return GetOverlappedResult(h, ref ov, out transferred, false);
  }

  private static bool SendWrite(IntPtr h, byte[] packet, int timeoutMs) {
    // Prefer HidD_SetOutputReport first (usually non-blocking).
    if (HidD_SetOutputReport(h, packet, packet.Length)) return true;

    OVERLAPPED ov = new OVERLAPPED();
    ov.hEvent = CreateEvent(IntPtr.Zero, true, false, null);
    try {
      int written;
      bool ok = WriteFile(h, packet, packet.Length, out written, ref ov);
      int err = Marshal.GetLastWin32Error();
      if (!ok && err != 997) return false; // 997 = ERROR_IO_PENDING
      if (ok) return written > 0;
      if (!WaitIo(h, ref ov, timeoutMs, out written)) return false;
      return written > 0;
    } finally {
      if (ov.hEvent != IntPtr.Zero) CloseHandle(ov.hEvent);
    }
  }

  public static string Probe() {
    string[] paths = FindDevicePaths();
    return "{\"ok\":true,\"devices\":" + paths.Length + "}";
  }

  public static string SetStyle(int style) {
    if (style < 0 || style > 4) throw new ArgumentOutOfRangeException("style");
    IntPtr h = OpenDevice(true);
    try {
      byte[] packet = BuildPacket(PropCrosshair, (ushort)style, true);
      if (!SendWrite(h, packet, 800)) throw new Exception("HID write failed: " + Marshal.GetLastWin32Error());
      bool enabled = style > 0;
      return "{\"ok\":true,\"enabled\":" + (enabled ? "true" : "false") + ",\"value\":" + style + ",\"style\":" + style + ",\"method\":\"hid-e037\"}";
    } finally { CloseHandle(h); }
  }
}

// MO32U2 Sidekick uses VCP 0xEF for its HDMI/DDC crosshair backend.
// Resolve the model from Windows before accessing this vendor-specific code.
public static class GbDdcCrosshair {
  private const byte CrosshairCode = 0xEF;

  [StructLayout(LayoutKind.Sequential)]
  private struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct MONITORINFOEX {
    public int cbSize;
    public RECT rcMonitor, rcWork;
    public uint dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
    public uint StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string description;
  }
  private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);
  [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc callback, IntPtr data);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE info, uint flags);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool DestroyPhysicalMonitors(uint count, [In] PHYSICAL_MONITOR[] monitors);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitor, byte code, out uint type, out uint current, out uint maximum);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);

  private static int ReadStyle(IntPtr monitor) {
    uint type, current, maximum;
    if (!GetVCPFeatureAndVCPFeatureReply(monitor, CrosshairCode, out type, out current, out maximum)) {
      throw new Exception("AIM DDC read failed: " + Marshal.GetLastWin32Error());
    }
    // Value 5 is Sidekick's custom crosshair; preserve it when reading status.
    if (current > 5) throw new Exception("Unexpected AIM DDC value: " + current);
    return (int)current;
  }

  private static string Run(int requestedStyle) {
    string result = null;
    Exception failure = null;
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data) {
      var info = new MONITORINFOEX(); info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
      if (!GetMonitorInfo(monitor, ref info)) return true;
      var device = new DISPLAY_DEVICE(); device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (!EnumDisplayDevices(info.szDevice, 0, ref device, 0)) return true;
      if (device.DeviceID == null || device.DeviceID.IndexOf("MONITOR\\GBT3217\\", StringComparison.OrdinalIgnoreCase) < 0) return true;

      try {
        uint count;
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) || count != 1) {
          throw new Exception("MO32U2 DDC monitor handle unavailable or ambiguous");
        }
        var physical = new PHYSICAL_MONITOR[count];
        if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical)) {
          throw new Exception("MO32U2 DDC open failed: " + Marshal.GetLastWin32Error());
        }
        try {
          // A physical monitor handle of zero is valid on this display driver.
          IntPtr handle = physical[0].hPhysicalMonitor;
          int current = ReadStyle(handle);
          if (requestedStyle >= 0) {
            if (!SetVCPFeature(handle, CrosshairCode, (uint)requestedStyle)) {
              throw new Exception("AIM DDC write failed: " + Marshal.GetLastWin32Error());
            }
            for (int attempt = 0; attempt < 3; attempt++) {
              Thread.Sleep(120);
              current = ReadStyle(handle);
              if (current == requestedStyle) break;
            }
            if (current != requestedStyle) throw new Exception("AIM DDC verification failed: requested " + requestedStyle + ", read " + current);
          }
          result = "{\"ok\":true,\"enabled\":" + (current > 0 ? "true" : "false") + ",\"value\":" + current + ",\"style\":" + current + ",\"devices\":0,\"source\":\"monitor\",\"method\":\"ddc-ef\"}";
        } finally { DestroyPhysicalMonitors(count, physical); }
      } catch (Exception error) { failure = error; }
      return false;
    }, IntPtr.Zero);
    if (failure != null) throw failure;
    if (result == null) throw new Exception("Gigabyte MO32U2 DDC display not found");
    return result;
  }

  public static string Status() { return Run(-1); }
  public static string SetStyle(int style) {
    if (style < 0 || style > 4) throw new ArgumentOutOfRangeException("style");
    return Run(style);
  }
}
'@

if (-not ('GbHidCrosshair' -as [type])) { try {
  Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System') -ErrorAction Stop | Out-Null
} catch {
  if ($_.Exception.Message -notmatch 'already exists') { throw }
} }

function Read-LocalState {
  if (-not (Test-Path -LiteralPath $StateFile)) {
    return [pscustomobject]@{ enabled = $false; style = 1; value = 0 }
  }
  try {
    return Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{ enabled = $false; style = 1; value = 0 }
  }
}

function Write-LocalState($enabled, $style, $value) {
  $payload = @{
    enabled = [bool]$enabled
    style = [int]$style
    value = [int]$value
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  } | ConvertTo-Json -Compress
  Set-Content -LiteralPath $StateFile -Value $payload -Encoding UTF8
}

function Get-CrosshairState {
  $st = Read-LocalState
  $probe = [GbHidCrosshair]::Probe() | ConvertFrom-Json
  if ($probe.devices -gt 0) {
    return [pscustomobject]@{
      ok = $true
      enabled = [bool]$st.enabled
      value = [int]$st.value
      style = [int]$(if ($st.style -gt 0) { $st.style } else { 1 })
      devices = [int]$probe.devices
      source = 'cache'
      method = 'hid-e037'
    }
  }
  $live = [GbDdcCrosshair]::Status() | ConvertFrom-Json
  if ($live.style -lt 1 -or $live.style -gt 4) {
    $live.style = [int]$(if ($st.style -ge 1 -and $st.style -le 4) { $st.style } else { 1 })
  }
  return $live
}

function Set-CrosshairStyle([int]$style) {
  try {
    return [GbHidCrosshair]::SetStyle($style)
  } catch {
    $hidError = $_.Exception.Message
    try { return [GbDdcCrosshair]::SetStyle($style) }
    catch { throw "USB AIM: $hidError; DDC AIM: $($_.Exception.Message)" }
  }
}

try {
  switch ($Action) {
    'status' {
      Get-CrosshairState | ConvertTo-Json -Compress
    }
    'off' {
      $raw = Set-CrosshairStyle 0
      $obj = $raw | ConvertFrom-Json
      if (-not $obj.ok) { throw $obj.error }
      Write-LocalState $false 1 0
      $raw
    }
    'on' {
      $s = if ($Value -ge 1 -and $Value -le 4) { $Value } elseif ($Style -ge 1) { $Style } else { 1 }
      $raw = Set-CrosshairStyle $s
      $obj = $raw | ConvertFrom-Json
      if (-not $obj.ok) { throw $obj.error }
      Write-LocalState $true $s $s
      $raw
    }
    'set' {
      $s = if ($Value -ge 0) { $Value } else { $Style }
      if ($s -lt 0 -or $s -gt 4) { throw "Style/value must be 0..4" }
      $raw = Set-CrosshairStyle $s
      $obj = $raw | ConvertFrom-Json
      if (-not $obj.ok) { throw $obj.error }
      Write-LocalState ($s -gt 0) $(if ($s -gt 0) { $s } else { 1 }) $s
      $raw
    }
    'toggle' {
      $st = Get-CrosshairState
      if ($st.enabled) {
        $raw = Set-CrosshairStyle 0
        Write-LocalState $false $(if ($st.style -gt 0) { $st.style } else { 1 }) 0
        $raw
      } else {
        $s = if ($Style -ge 1) { $Style } elseif ($st.style -ge 1) { [int]$st.style } else { 1 }
        $raw = Set-CrosshairStyle $s
        Write-LocalState $true $s $s
        $raw
      }
    }
  }
} catch {
  [pscustomobject]@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
  exit 1
}
