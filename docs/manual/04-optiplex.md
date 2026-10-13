# 4. Set up OptiPlex (cobra-arcade, Windows 11, 10.6.9.30)

**Result:** the cabinet boots straight into Big Box, ROMs come from the SGIN's `roms` share, and it's patched and activated.

🔌 OptiPlex Ethernet → your switch the whole time. Unplug it only if you want Windows setup to skip network sign-in (Rufus's option already handles that).

## 4.1 Prep

- [ ] Backed up: LaunchBox folder, RetroArch `saves states system config playlists` + `.hi` files, license key (`(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey`)
- [ ] BIOS (F2): latest version, SATA AHCI, UEFI boot, Secure Boot on, Security → TPM 2.0 Security on (the 7040 has a discrete TPM, not PTT; if it reports TPM 1.2, flash Dell's TPM 2.0 firmware update first), AC Recovery → Power On
- [ ] Windows 11 USB from Rufus with "remove TPM/Secure Boot/RAM requirement" + "remove online account" ticked
- [ ] Boot the stick: **F12** at the Dell logo → UEFI USB
- [ ] **Unplug the WD data drive's SATA cable first** (it keeps its files; see 4.6). Then the system disk is the only one Setup can see.
- [ ] Setup: Custom install → delete every partition on the **system disk** → select the unallocated space → Next. Plug the WD drive back in after Windows is installed.
- [ ] Out-of-box: region/keyboard, local account `arcade` with a generated password, all privacy toggles off
- [ ] OPNsense static mapping `.30`

## 4.2 Software and shares

GPU driver: current AMD Adrenalin does **not** support the Oland (R7 250-class, GCN 1) card. Use the **Windows Legacy Driver** from amd.com/support → Graphics → Radeon R7 Series → your card, or let Windows Update install its driver. ⚠️ Verify the exact legacy version on AMD's page.

PowerShell **as Admin** (right-click Start → Terminal (Admin)):

```powershell
Rename-Computer cobra-arcade
winget install -e --id Valve.Steam
winget install -e --id Libretro.RetroArch
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
```

PowerShell **not** as Admin (plain Terminal). A drive mapped from an elevated window is invisible to normal apps like Big Box and RetroArch:

```powershell
cmdkey /add:cobra-stream /user:arcade /pass:<samba arcade password>
New-SmbMapping -LocalPath R: -RemotePath \\cobra-stream\roms -Persistent $true
Restart-Computer
```

## 4.3 LaunchBox, Big Box and RetroArch

The cabinet plays everything natively: LaunchBox/Big Box is the menu, RetroArch does the emulating, and the ROMs stay on the SGIN. The web arcade (RomM + EmulatorJS on the SGIN, part 3) reads the **same** `roms` folder, so a game added once shows up in both.

**ROM folder names.** Name each system's folder the way RomM expects (`roms/<platform>/`, e.g. `roms/snes`, `roms/gba`, `roms/n64`, `roms/arcade`). LaunchBox doesn't care about names, RomM does. ⚠️ Verify the exact slugs on RomM's "Supported platforms" page before renaming a big collection.

- [ ] LaunchBox installer from launchbox-app.com → restore the backed-up LaunchBox folder over it (to `D:\LaunchBox` if the WD drive has room, otherwise `C:\LaunchBox`)
- [ ] **Emulator:** Tools → Manage → Emulators → Add → RetroArch → path to `retroarch.exe` (winget puts it in `C:\RetroArch-Win64\` ⚠️ Verify). On the **Associated Platforms** tab, let LaunchBox fill in its default core for each platform, then set Arcade to **FinalBurn Neo** (`fbneo_libretro.dll`) or **MAME 2003-Plus** to match your romset.
- [ ] **Importing games:** Tools → Import → ROM Files → pick `R:\<platform>` → when asked, choose **use the files in their current location**. The other choice copies every ROM onto the cabinet's disk.
- [ ] Big Box: Options → Startup → start Big Box on Windows startup
- [ ] RetroArch: copy back `saves states system config playlists`. Its own ROM browser can point at `R:\` (Settings → Directory → File Browser), but day to day LaunchBox launches the games.
- [ ] Tankstick: map in RetroArch → Settings → Input → Port 1/2 binds, Save autoconfig. LaunchBox/Big Box: Options → Controllers, map the same stick for menu navigation.
- [ ] Netplay host: Firewall allow TCP 55435 inbound from LAN; OPNsense port forward only if friends join from outside
- [ ] Auto-login: Sysinternals Autologon (`winget install -e --id Microsoft.Sysinternals.Autologon`), user `arcade`
- [ ] Windows Update until nothing left; Settings → Activation shows activated

**Arcade romsets must match the core.** FinalBurn Neo and MAME 2003-Plus each need their own romset version, and a zip that works in one often fails in the other. The browser arcade uses the same cores (EmulatorJS ships FinalBurn Neo and MAME 2003-Plus builds), so keep one folder per set: `roms/arcade` for the set you play most, and set the matching core in both LaunchBox and RomM's platform settings.

## 4.4 Hiscores on the cabinet

Hiscores are a **per-core** option in RetroArch, not a global setting. Load a game, then Quick Menu → Core Options:

- **FinalBurn Neo:** "Hiscores" on. Needs `hiscore.dat` in `system\fbneo\`.
- **MAME 2003-Plus:** "Hiscores" on. Its `hiscore.dat` ships in the core's system folder, `system\mame2003-plus\`.
- [ ] Play one game, set a score, quit, then find the new `.hi` file: `Get-ChildItem C:\RetroArch-Win64 -Recurse -Filter *.hi | Sort-Object LastWriteTime -Descending | Select-Object -First 5 FullName`. Write the folder down; the hiscore agent watches it (design in [07-hiscore-platform.md](07-hiscore-platform.md)).

## 4.5 Back up the cabinet's own files to the SGIN

Saves, save states, `.hi` files and the LaunchBox database live only on the cabinet. Copy them to the pool nightly, where the vault backup (part 5) picks them up. One small script does both this and 4.6.

Create the folder with `New-Item -ItemType Directory -Force C:\Cobra`, then save this as `C:\Cobra\nightly-copy.ps1` (Notepad, then "Save as type: All files"):

```powershell
# Nightly copies for cobra-arcade. robocopy /E /XO adds and updates, never deletes.
$log = 'C:\Cobra\nightly-copy.log'
$pool = '\\cobra-stream\media'
$ra = 'C:\RetroArch-Win64'      # your RetroArch folder
$lb = 'D:\LaunchBox'            # or C:\LaunchBox

# 1) cabinet -> pool (4.5)
$up = @{
  "$ra\saves"     = "$pool\backups\arcade\RetroArch\saves"
  "$ra\states"    = "$pool\backups\arcade\RetroArch\states"
  "$ra\system"    = "$pool\backups\arcade\RetroArch\system"
  "$ra\config"    = "$pool\backups\arcade\RetroArch\config"
  "$ra\playlists" = "$pool\backups\arcade\RetroArch\playlists"
  "$lb\Data"      = "$pool\backups\arcade\LaunchBox\Data"
}
# 2) pool -> D: (4.6). Edit the list: the pool folders you'd hate to lose.
$down = 'music', 'roms', 'books', 'audiobooks', 'comics', 'scans', 'backups'

Add-Content $log "=== $(Get-Date)"
foreach ($src in $up.Keys) {
  if (Test-Path $src) { robocopy $src $up[$src] /E /XO /R:2 /W:5 /NP /NFL /NDL /LOG+:$log | Out-Null }
}
foreach ($f in $down) {
  robocopy "$pool\$f" "D:\Cobra-copy\$f" /E /XO /R:2 /W:5 /NP /NFL /NDL /LOG+:$log | Out-Null
}
```

Register it to run every night (plain PowerShell as `arcade`):

```powershell
$a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Cobra\nightly-copy.ps1'
$t = New-ScheduledTaskTrigger -Daily -At 3:30am
Register-ScheduledTask -TaskName 'Cobra nightly copy' -Action $a -Trigger $t `
  -Settings (New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12))
Start-ScheduledTask 'Cobra nightly copy'      # first run now; the first pull to D: can take hours
```

- `-StartWhenAvailable`: if the cabinet was off at 3:30, it runs at next boot.
- ⚠️ Verify the folder names under your RetroArch install match the ones in `$up`.

## 4.6 The OptiPlex's WD drive

It stays in the OptiPlex as `D:` (if it's the OptiPlex's **only** disk, it's the system disk instead and only job 1 applies), with two jobs:

1. **The cabinet's local game drive.** Steam library, LaunchBox and its media (box art, videos), so the menu stays fast and doesn't depend on the network.
2. **An extra copy of what you can't replace, until the vault drive arrives (and after).** The `$down` part of the script in 4.5 pulls those pool folders into `D:\Cobra-copy` every night. `/E /XO` never deletes, so a file removed by mistake on the pool is still here. Check `D:`'s free space against what you list; movies and TV are the big ones and you can re-rip or re-buy those.

- [ ] Before relying on it: `D:` shows healthy in `Get-PhysicalDisk | Select FriendlyName, HealthStatus` and has no SMART warnings in CrystalDiskInfo

## Done when

- [ ] Power on → Big Box loads by itself → a game from `R:\` plays with the stick
- [ ] The same game shows in the web arcade (`arcade.songofeo.com`) after a RomM library scan
- [ ] Next morning: `C:\Cobra\nightly-copy.log` has no `ERROR` lines
