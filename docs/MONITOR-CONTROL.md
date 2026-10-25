# MO32U2 control behavior

The brightness dial press switches Windows HDR. The plugin selects **Standard**
for SDR; the tested monitor returns to normal **HDR** on entering HDR, verified
in its physical OSD. On entering SDR, profile
selection completes before brightness is read and shown on all visible controls.
Selecting another SDR profile also refreshes neighboring brightness controls.

## HDR and SDR are separate monitor settings

On the tested MO32U2, the physical OSD stores independent HDR preset settings.
In the 2026-10-25 investigation the user set HDR Movie brightness to 12, then 13,
and HDR Game to 34. Standard DDC brightness and the installed GIGABYTE USB
library continued to report 60. Turning the MiraBox brightness dial changed that
software-visible register, but did not change the HDR preset brightness in the
physical OSD. The Sidekick application did not expose an HDR settings section.

Those observations establish a limitation of the interfaces used here, not a
claim that no other firmware command could exist. The plugin must not present
the SDR register as HDR preset brightness, invent HDR profile IDs, or substitute
Windows SDR white level for the requested monitor setting.

| Control | SDR | HDR on MO32U2 |
|---|---|---|
| Brightness dial rotation | Monitor brightness 0–100 | `HDR OSD`; no SDR brightness write |
| Brightness dial press | Enter HDR and select normal HDR | Enter SDR and select Standard, then read brightness |
| Picture dial rotation | SDR profiles from the monitor's Sidekick catalog | `HDR OSD`; no SDR profile IDs |
| Default profile after a toggle | Standard, with DDC readback | Normal HDR on mode entry, checked in the physical OSD |

Sidekick's HDMI library uses VCP **0xE7** for picture profiles. Standard VCP
**0x14** is color temperature and must not be used for profile selection. SDR
profile writes are confirmed with matching 0xE7 readback. In two controlled tests,
SDR -> HDR followed by 0xE7 value 0 or 1 both left the monitor on normal HDR,
as checked by the user in the OSD. These tests did not establish HDR preset
addressing, so the plugin sends no speculative HDR preset IDs. The getter
continues to report the SDR profile while HDR is active and cannot verify the
active HDR preset. Returning to normal HDR on mode entry is observed behavior
of this monitor, not a separately confirmed HDR-select API.

The UI shows `HDR OSD` for the unavailable controls and explains the limitation
in their settings. Old HDR percentages and the guessed HDR profile catalog are
not restored from cache. The helper scripts also reject unsupported writes,
including when HDR changes after the UI has queued an SDR operation.

## State acquisition and resource use

One Node process sends fixed JSON commands to one stock Windows PowerShell
session. The existing Win32 interop types load once per session. Native commands
are serialized; interactive writes have priority over queued background reads.
The session reconnects after display changes so it does not keep stale driver
state. A separate custom executable or MSBuild step is not used.

Only visible controls subscribe to shared polling for their monitor. Duplicate
controls share a read, polls do not overlap, and failures back off. Defaults are
15 seconds for brightness, 30 seconds for HDR/picture state, and 60 seconds for
refresh rate. AIM has no repeating poll. Windows display events refresh affected
controls immediately. In MO32U2 HDR, brightness and picture status use Windows
display metadata and do not poll the unrelated SDR registers in the monitor.

Brightness rotation previews immediately and combines turns into one write
after 280 ms of inactivity. Picture browsing applies after 850 ms. A mode or
profile change cancels old pending brightness writes and refreshes the new
baseline. UI cache writes are combined for 500 ms, atomic, and skipped when
unchanged. Further periodic polling reductions should preserve prompt detection
of changes made directly in the monitor OSD or Sidekick.

The earlier 60-second idle measurements on the validation PC, with 32 logical
processors, showed average plugin-tree CPU falling from 2.524% to 0.014%, and
peak working memory from 489.5 to 167.8 MB after moving to the persistent
session. The warmed sample contained no new PowerShell or compiler processes.
These measurements exclude the Stream Dock host and are not an FPS benchmark.

The runtime uses process-scoped `RemoteSigned`, does not change system execution
policy or antivirus settings, and does not restore the custom worker objects
previously removed by Kaspersky. A successful test does not guarantee how a
future antivirus heuristic will classify a process.
