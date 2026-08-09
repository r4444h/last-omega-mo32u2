# Community releases

Packaged installers are produced by `scripts/pack.ps1` and published on
**GitHub Releases** (not committed to git):

- `LastOmega-<version>-windows.zip` — unpack into Stream Dock `plugins\`
- `LastOmega-<version>-windows.streamDockPlugin` — same zip bytes, alternate extension
- `LastOmega-<version>-windows.sha256` — checksum

```powershell
.\scripts\pack.ps1
.\scripts\install-release.ps1 -ZipPath .\dist\LastOmega-0.5.5-windows.zip
```
