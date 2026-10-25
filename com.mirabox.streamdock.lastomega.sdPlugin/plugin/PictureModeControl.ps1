#Requires -Version 5.1
<#
.SYNOPSIS
  Gigabyte MO32U2 SDR Picture Mode via VCP 0xE7, with USB HID fallback.
  HDR preset commands are not established; never send SDR mode IDs in HDR.

.EXAMPLE
  .\PictureModeControl.ps1 -Action status -NameFilter MO32U2
  .\PictureModeControl.ps1 -Action set -Value 1 -NameFilter MO32U2
  .\PictureModeControl.ps1 -Action delta -Delta 1 -NameFilter MO32U2
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('status', 'set', 'delta', 'list', 'default')]
  [string]$Action,

  [string]$NameFilter = 'MO32U2',

  [int]$Value = -1,

  [int]$Delta = 0,

  # Optional JSON arrays of {id,name,short} — id is hardware value
  [string]$SdrModesJson = '',
  [string]$HdrModesJson = '',
  [Nullable[bool]]$KnownHdrEnabled = $null
)

$ErrorActionPreference = 'Stop'
$StateFile = Join-Path $PSScriptRoot 'picture-mode-state.json'
$ModesCacheFile = Join-Path $PSScriptRoot 'picture-modes-cache.json'
$HdrScript = Join-Path $PSScriptRoot 'HdrControl.ps1'
$SidekickDir = 'C:\Program Files\GIGABYTE\Control Center\Lib\Sidekick'
$SidekickDll = Join-Path $SidekickDir 'OSDSidekick.dll'

# Fallback only if Sidekick is missing / FillPicture fails
$DefaultSdr = @(
  @{ id = 0; name = 'Standard'; short = 'STD' },
  @{ id = 1; name = 'FPS'; short = 'FPS' },
  @{ id = 2; name = 'MOBA'; short = 'MOBA' },
  @{ id = 3; name = 'RPG'; short = 'RPG' },
  @{ id = 4; name = 'Racing'; short = 'RACE' },
  @{ id = 5; name = 'Movie'; short = 'MOV' },
  @{ id = 6; name = 'Reader'; short = 'READ' },
  @{ id = 7; name = 'sRGB'; short = 'sRGB' },
  @{ id = 8; name = 'Custom'; short = 'CUST' },
  @{ id = 9; name = 'ECO'; short = 'ECO' }
)
$DefaultHdr = @()

$cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class GbPictureMode {
  public const int VendorId = 0x0BDA;
  public const int ProductId = 0x1100;
  public const ushort PropPicture = 0xE02C;
  // 0x14 is color temperature. Sidekick's HDMI library uses 0xE7 for profiles.
  public const byte VcpPicture = 0xE7;

  private const uint DIGCF_PRESENT = 0x2;
  private const uint DIGCF_DEVICEINTERFACE = 0x10;
  private const uint GENERIC_READ = 0x80000000;
  private const uint GENERIC_WRITE = 0x40000000;
  private const uint FILE_SHARE_READ = 0x1;
  private const uint FILE_SHARE_WRITE = 0x2;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_ATTRIBUTE_NORMAL = 0x80;
  private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
  private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

  [StructLayout(LayoutKind.Sequential)]
  private struct SP_DEVICE_INTERFACE_DATA {
    public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved;
  }
  [StructLayout(LayoutKind.Sequential)]
  private struct HIDD_ATTRIBUTES {
    public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber;
  }
  [StructLayout(LayoutKind.Sequential)]
  private struct OVERLAPPED {
    public IntPtr Internal; public IntPtr InternalHigh; public int Offset; public int OffsetHigh; public IntPtr hEvent;
  }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
  private struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szPhysicalMonitorDescription;
  }
  [StructLayout(LayoutKind.Sequential)]
  private struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct MONITORINFOEX {
    public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags;
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

  [DllImport("hid.dll")] private static extern void HidD_GetHidGuid(out Guid HidGuid);
  [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
  [DllImport("hid.dll", SetLastError = true)] private static extern bool HidD_SetOutputReport(IntPtr h, byte[] b, int n);
  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr SetupDiGetClassDevs(ref Guid c, IntPtr e, IntPtr w, uint f);
  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid c, uint i, ref SP_DEVICE_INTERFACE_DATA a);
  [DllImport("setupapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA a, IntPtr detail, int sz, out int req, IntPtr info);
  [DllImport("setupapi.dll", SetLastError = true)] private static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
  [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  private static extern IntPtr CreateFile(string n, uint a, uint sh, IntPtr sec, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, ref OVERLAPPED ov);
  [DllImport("kernel32.dll", SetLastError = true)]
  private static extern bool GetOverlappedResult(IntPtr h, ref OVERLAPPED ov, out int x, bool wait);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CancelIo(IntPtr h);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateEvent(IntPtr a, bool m, bool i, string n);

  [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, MonitorEnumProc c, IntPtr d);
  private delegate bool MonitorEnumProc(IntPtr h, IntPtr a, IntPtr b, IntPtr c);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE info, uint flags);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, ref uint c);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint c, [Out] PHYSICAL_MONITOR[] m);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool DestroyPhysicalMonitors(uint c, [In] PHYSICAL_MONITOR[] m);
  [DllImport("dxva2.dll", SetLastError = true)]
  private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out IntPtr t, out uint cur, out uint max);
  [DllImport("dxva2.dll", SetLastError = true)] private static extern bool SetVCPFeature(IntPtr h, byte code, uint val);

  private static byte[] BuildPacket(ushort prop, ushort value) {
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

  private static IntPtr OpenHid() {
    Guid g; HidD_GetHidGuid(out g);
    IntPtr info = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    try {
      for (uint i = 0; ; i++) {
        var ifd = new SP_DEVICE_INTERFACE_DATA();
        ifd.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
        if (!SetupDiEnumDeviceInterfaces(info, IntPtr.Zero, ref g, i, ref ifd)) break;
        int req; SetupDiGetDeviceInterfaceDetail(info, ref ifd, IntPtr.Zero, 0, out req, IntPtr.Zero);
        if (req <= 0) continue;
        IntPtr detail = Marshal.AllocHGlobal(req);
        try {
          Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 4 + Marshal.SystemDefaultCharSize);
          if (!SetupDiGetDeviceInterfaceDetail(info, ref ifd, detail, req, out req, IntPtr.Zero)) continue;
          string path = Marshal.PtrToStringAuto(new IntPtr(detail.ToInt64() + 4));
          IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED, IntPtr.Zero);
          if (h == INVALID_HANDLE_VALUE) continue;
          var attr = new HIDD_ATTRIBUTES(); attr.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
          if (HidD_GetAttributes(h, ref attr) && attr.VendorID == VendorId && attr.ProductID == ProductId) return h;
          CloseHandle(h);
        } finally { Marshal.FreeHGlobal(detail); }
      }
    } finally { SetupDiDestroyDeviceInfoList(info); }
    throw new Exception("Gigabyte Realtek HID 0BDA:1100 not found");
  }

  private static bool SendHid(IntPtr h, byte[] packet) {
    if (HidD_SetOutputReport(h, packet, packet.Length)) return true;
    var ov = new OVERLAPPED();
    ov.hEvent = CreateEvent(IntPtr.Zero, true, false, null);
    try {
      int written;
      bool ok = WriteFile(h, packet, packet.Length, out written, ref ov);
      int err = Marshal.GetLastWin32Error();
      if (!ok && err != 997) return false;
      if (ok) return written > 0;
      if (WaitForSingleObject(ov.hEvent, 800) != 0) { CancelIo(h); return false; }
      return GetOverlappedResult(h, ref ov, out written, false) && written > 0;
    } finally {
      if (ov.hEvent != IntPtr.Zero) CloseHandle(ov.hEvent);
    }
  }

  private static bool WithPhysical(Func<IntPtr, bool> fn) {
    bool done = false; bool result = false;
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (hMon, a, b, c) => {
      if (done) return true;
      var info = new MONITORINFOEX(); info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
      if (!GetMonitorInfo(hMon, ref info)) return true;
      var device = new DISPLAY_DEVICE(); device.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (!EnumDisplayDevices(info.szDevice, 0, ref device, 0) || device.DeviceID == null ||
          device.DeviceID.IndexOf("MONITOR\\GBT3217\\", StringComparison.OrdinalIgnoreCase) < 0) return true;
      uint count = 0;
      GetNumberOfPhysicalMonitorsFromHMONITOR(hMon, ref count);
      if (count != 1) return true;
      var arr = new PHYSICAL_MONITOR[count];
      if (!GetPhysicalMonitorsFromHMONITOR(hMon, count, arr)) return true;
      try { result = fn(arr[0].hPhysicalMonitor); done = true; }
      finally { DestroyPhysicalMonitors(count, arr); }
      return true;
    }, IntPtr.Zero);
    return result;
  }

  public static int GetVcp() {
    int value = -1;
    WithPhysical(h => {
      for (int attempt = 0; attempt < 3; attempt++) {
        IntPtr t; uint cur = 0, max = 0;
        if (GetVCPFeatureAndVCPFeatureReply(h, VcpPicture, out t, out cur, out max) && cur <= 9 && max >= cur) {
          value = (int)cur;
          return true;
        }
        if (attempt < 2) Thread.Sleep(150);
      }
      return false;
    });
    return value;
  }

  public static bool SetVcp(int value) {
    bool ok = false;
    WithPhysical(h => {
      ok = SetVCPFeature(h, VcpPicture, (uint)value);
      return ok;
    });
    return ok;
  }

  public static bool SetHid(int value) {
    IntPtr h = OpenHid();
    try {
      return SendHid(h, BuildPacket(PropPicture, (ushort)value));
    } finally { CloseHandle(h); }
  }

  public static string SetBoth(int value) {
    bool hidOk = false, vcpOk = false;
    Exception hidErr = null;
    try { vcpOk = SetVcp(value); } catch { }
    if (!vcpOk) { try { hidOk = SetHid(value); } catch (Exception ex) { hidErr = ex; } }
    if (!hidOk && !vcpOk) {
      throw new Exception(hidErr != null ? hidErr.Message : "picture mode set failed");
    }
    int read = -1;
    for (int attempt = 0; attempt < 3; attempt++) {
      Thread.Sleep(150);
      read = GetVcp();
      if (read == value) break;
    }
    if (read != value) throw new Exception("Picture profile change was not confirmed by the monitor.");
    return "{\"ok\":true,\"value\":" + value + ",\"read\":" + read +
           ",\"hidOk\":" + (hidOk ? "true" : "false") +
           ",\"vcpOk\":" + (vcpOk ? "true" : "false") +
           ",\"rtkOk\":false}";
  }
}
'@

if (-not ('GbPictureMode' -as [type])) { try {
  Add-Type -TypeDefinition $cs -ErrorAction Stop | Out-Null
} catch {
  if ($_.Exception.Message -notmatch 'already exists') { throw }
} }

function Get-ShortLabel([string]$name) {
  $n = ([string]$name).Trim()
  if (-not $n) { return '?' }
  $known = @{
    'Standard' = 'STD'
    'FPS' = 'FPS'
    'MOBA' = 'MOBA'
    'RPG' = 'RPG'
    'Racing' = 'RACE'
    'Movie' = 'MOV'
    'Reader' = 'READ'
    'sRGB' = 'sRGB'
    'Custom' = 'CUST'
    'ECO' = 'ECO'
    'Gaming' = 'GAME'
    'RTS/RPG' = 'RTS'
    'Arcade' = 'ARCD'
    'Aorus' = 'AOR'
    'Gamer 1' = 'G1'
    'Gamer 2' = 'G2'
    'Gamer 3' = 'G3'
  }
  if ($known.ContainsKey($n)) { return $known[$n] }
  if ($n.Length -le 5) { return $n }
  return $n.Substring(0, [Math]::Min(4, $n.Length)).ToUpperInvariant()
}

function Convert-SidekickList($list) {
  $out = @()
  foreach ($item in @($list)) {
    $id = [int]$item.value
    $name = [string]$item.Mode_Name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $out += @{
      id = $id
      name = $name
      short = (Get-ShortLabel $name)
      modeId = [int]$item.Mode_ID
    }
  }
  return $out
}

function Import-SidekickModes([string]$model, [switch]$Force) {
  $modelKey = if ($model) { $model } else { 'MO32U2' }

  if (-not $Force -and (Test-Path -LiteralPath $ModesCacheFile)) {
    try {
      $cached = Get-Content -LiteralPath $ModesCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
      $ageMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$cached.updatedAt
      if ($cached.catalogVersion -eq 2 -and $cached.model -eq $modelKey -and $cached.sdrModes -and $ageMs -lt 7 * 24 * 3600 * 1000) {
        $sdr = @($cached.sdrModes | ForEach-Object {
          @{ id = [int]$_.id; name = [string]$_.name; short = [string]$(if ($_.short) { $_.short } else { Get-ShortLabel $_.name }) }
        })
        $hdr = @()
        if ($sdr.Count -gt 0) {
          return @{
            ok = $true
            source = 'cache'
            model = $modelKey
            sdrType = [int]$cached.sdrType
            hdrType = [int]$cached.hdrType
            sdrModes = $sdr
            hdrModes = $hdr
          }
        }
      }
    } catch {}
  }

  if (-not (Test-Path -LiteralPath $SidekickDll)) {
    return @{
      ok = $true
      source = 'fallback'
      model = $modelKey
      sdrType = -1
      hdrType = -1
      sdrModes = $DefaultSdr
      hdrModes = $DefaultHdr
      warning = 'OSDSidekick.dll not found'
    }
  }

  $oldDir = Get-Location
  $oldPath = $env:PATH
  try {
    Set-Location $SidekickDir
    $env:PATH = "$SidekickDir;$oldPath"
    [Environment]::CurrentDirectory = $SidekickDir
    Add-Type -Path $SidekickDll -ErrorAction Stop

    $oi = [Activator]::CreateInstance([OSDSidekick.OSD_Interface])
    $sdrType = [int]$oi.PictureModeType($modelKey)
    $hdrType = -1 # FillPicture tables describe SDR families, not HDR presets.

    $amType = [OSDSidekick.OSD_Interface].GetNestedType('All_Monitor')
    $fill = [OSDSidekick.OSD_Interface].GetMethod('FillPicture')

    $fillOne = {
      param([int]$picType)
      $am = [Activator]::CreateInstance($amType)
      $am.Win_ID_Map_model = $modelKey
      $am.ProductIDMapModel = $modelKey
      $am.ModelMapID = $modelKey
      $am.Soc_model = $modelKey
      $am.PictureModeType = $picType
      $am.AOR_GBT_flag = 1
      $am.DDC_Type = 1
      $callArgs = New-Object 'object[]' 1
      $callArgs[0] = $am
      return $fill.Invoke($oi, $callArgs)
    }

    $sdrRaw = & $fillOne $sdrType
    $sdrModes = @(Convert-SidekickList $sdrRaw)
    $hdrModes = @()
    if ($sdrModes.Count -eq 0) { $sdrModes = $DefaultSdr }

    $payload = @{
      model = $modelKey
      catalogVersion = 2
      sdrType = $sdrType
      hdrType = $hdrType
      sdrModes = @($sdrModes | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; short = $_.short } })
      hdrModes = @($hdrModes | ForEach-Object { [ordered]@{ id = $_.id; name = $_.name; short = $_.short } })
      updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
      source = 'sidekick'
    }
    ($payload | ConvertTo-Json -Compress -Depth 6) | Set-Content -LiteralPath $ModesCacheFile -Encoding UTF8

    return @{
      ok = $true
      source = 'sidekick'
      model = $modelKey
      sdrType = $sdrType
      hdrType = $hdrType
      sdrModes = $sdrModes
      hdrModes = $hdrModes
    }
  } catch {
    return @{
      ok = $true
      source = 'fallback'
      model = $modelKey
      sdrType = -1
      hdrType = -1
      sdrModes = $DefaultSdr
      hdrModes = $DefaultHdr
      warning = $_.Exception.Message
    }
  } finally {
    Set-Location $oldDir
    $env:PATH = $oldPath
  }
}

function Convert-ModeList($json, $fallback) {
  if ([string]::IsNullOrWhiteSpace($json)) { return $null }
  try {
    $parsed = $json | ConvertFrom-Json
    $list = @()
    foreach ($m in @($parsed)) {
      $id = [int]$m.id
      $name = [string]($m.name)
      $short = [string]($(if ($m.short) { $m.short } else { Get-ShortLabel $name }))
      if (-not $name) { continue }
      $list += @{ id = $id; name = $name; short = $short }
    }
    if ($list.Count -gt 0) { return $list }
  } catch {}
  return $null
}

function Get-HdrEnabled {
  try {
    $raw = & $HdrScript -Action status -NameFilter $NameFilter
    $line = ($raw | Out-String).Trim().Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 1
    $obj = $line | ConvertFrom-Json
    return [bool]$obj.display.hdrEnabled
  } catch {
    return $false
  }
}

function Read-LocalState {
  if (-not (Test-Path -LiteralPath $StateFile)) {
    return [pscustomobject]@{ sdrValue = 0; hdrValue = 0 }
  }
  try { return Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { return [pscustomobject]@{ sdrValue = 0; hdrValue = 0 } }
}

function Write-LocalState($sdrValue, $hdrValue) {
  $payload = @{
    sdrValue = [int]$sdrValue
    hdrValue = [int]$hdrValue
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  } | ConvertTo-Json -Compress
  Set-Content -LiteralPath $StateFile -Value $payload -Encoding UTF8
}

function Find-Index($modes, $value) {
  for ($i = 0; $i -lt $modes.Count; $i++) {
    if ([int]$modes[$i].id -eq [int]$value) { return $i }
  }
  return -1
}

function Build-Result($modes, $value, $hdrEnabled, $extra = @{}) {
  $idx = Find-Index $modes $value
  if ($idx -lt 0) { $idx = 0; $value = [int]$modes[0].id }
  $mode = $modes[$idx]
  $obj = [ordered]@{
    ok = $true
    controlAvailable = $true
    hdrEnabled = [bool]$hdrEnabled
    value = [int]$value
    index = [int]$idx
    name = [string]$mode.name
    short = [string]$mode.short
    label = [string]$mode.short
    modes = @($modes | ForEach-Object {
      [ordered]@{ id = [int]$_.id; name = [string]$_.name; short = [string]$_.short }
    })
  }
  foreach ($k in $extra.Keys) { $obj[$k] = $extra[$k] }
  $obj | ConvertTo-Json -Compress -Depth 5
}

try {
  $hdrEnabled = if ($null -ne $KnownHdrEnabled) { [bool]$KnownHdrEnabled } else { Get-HdrEnabled }
  if ($hdrEnabled) {
    $reason = 'Use the monitor OSD for HDR presets. Sidekick SDR profile IDs do not select the MO32U2 HDR presets.'
    if ($Action -in @('set', 'delta')) { throw $reason }
    [ordered]@{
      ok = $true; controlAvailable = $false; unavailableReason = $reason
      hdrEnabled = $true; value = $null; index = -1; name = 'Use monitor OSD'; short = 'HDR OSD'; label = 'HDR OSD'
      modes = @(); hdrModes = @(); sdrModes = $DefaultSdr; source = 'unsupported-hdr'
      # The tested monitor enters normal HDR on an SDR -> HDR transition.
      # E7 writes 0/1 did not establish independent HDR preset addressing.
      # The caller has just changed HDR mode; do not send an ignored SDR ID.
      defaultProfileApplied = $false
      defaultProfileSource = $(if ($Action -eq 'default') { 'monitor-on-hdr-entry' } else { $null })
    } | ConvertTo-Json -Compress -Depth 5
    return
  }
  $forceReload = ($Action -eq 'list')
  $loaded = Import-SidekickModes -model $NameFilter -Force:$forceReload
  $sdrOverride = Convert-ModeList $SdrModesJson $null
  $hdrOverride = Convert-ModeList $HdrModesJson $null
  $sdrModes = if ($sdrOverride) { $sdrOverride } else { @($loaded.sdrModes) }
  $hdrModes = if ($hdrOverride) { $hdrOverride } else { @($loaded.hdrModes) }
  $modes = if ($hdrEnabled) { $hdrModes } else { $sdrModes }
  $local = Read-LocalState
  if ($Action -eq 'default') { $Action = 'set'; $Value = 0 }

  switch ($Action) {
    'list' {
      [ordered]@{
        ok = $true
        hdrEnabled = $hdrEnabled
        source = $loaded.source
        model = $loaded.model
        sdrType = $loaded.sdrType
        hdrType = $loaded.hdrType
        warning = $loaded.warning
        sdrModes = $sdrModes
        hdrModes = $hdrModes
      } | ConvertTo-Json -Compress -Depth 6
    }
    'status' {
      $value = [GbPictureMode]::GetVcp()
      if ((Find-Index $modes $value) -lt 0) { throw 'Active SDR picture profile could not be read from the monitor.' }
      Build-Result $modes $value $hdrEnabled @{
        source = 'ddc-e7'
        model = $loaded.model
        sdrType = $loaded.sdrType
        hdrType = $loaded.hdrType
        catalogSource = $loaded.source
      }
    }
    'set' {
      if ($Value -lt 0) { throw 'Value required for set' }
      $idx = Find-Index $modes $Value
      if ($idx -lt 0) { throw "Value $Value is not in active mode list" }
      $raw = [GbPictureMode]::SetBoth($Value) | ConvertFrom-Json
      $final = [int]$Value
      if ($hdrEnabled) { Write-LocalState $local.sdrValue $final }
      else { Write-LocalState $final $local.hdrValue }
      Build-Result $modes $final $hdrEnabled @{
        hidOk = $raw.hidOk; vcpOk = $raw.vcpOk; rtkOk = $raw.rtkOk; read = $raw.read
        source = $loaded.source; model = $loaded.model
      }
    }
    'delta' {
      $read = [GbPictureMode]::GetVcp()
      if ((Find-Index $modes $read) -lt 0) { throw 'Active SDR picture profile could not be read from the monitor.' }
      $current = $read
      $idx = Find-Index $modes $current
      if ($idx -lt 0) { $idx = 0 }
      $n = $modes.Count
      $nextIdx = (($idx + $Delta) % $n + $n) % $n
      $nextVal = [int]$modes[$nextIdx].id
      $raw = [GbPictureMode]::SetBoth($nextVal) | ConvertFrom-Json
      $final = $nextVal
      if ($hdrEnabled) { Write-LocalState $local.sdrValue $final }
      else { Write-LocalState $final $local.hdrValue }
      Build-Result $modes $final $hdrEnabled @{
        hidOk = $raw.hidOk; vcpOk = $raw.vcpOk; rtkOk = $raw.rtkOk; read = $raw.read; delta = $Delta
        source = $loaded.source; model = $loaded.model
      }
    }
  }
} catch {
  $msg = $_.Exception.Message -replace '[\\\"\r\n]', ' '
  Write-Output ("{`"ok`":false,`"error`":`"$msg`"}")
  exit 1
}
