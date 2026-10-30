# 4. Set up OptiPlex (cobra-arcade, Windows 11, 10.6.9.30)

**Result:** the cabinet boots straight into Big Box, ROMs live on its own 4 TB drive (`D:\Roms`) and are copied each night to the SGIN for the web arcade, and it's patched and activated.

**Doing this part while the SGIN is busy (e.g. the wd1 rescue in 3.4r)?** Everything up to and including 4.4, plus 4.7, runs on the OptiPlex alone: it only needs cobra-switch port 3 and the Latitude for internet. Leave the SGIN, its hub, its drives and cobra-switch port 2 alone, and don't restart or reconfigure the switch. Three steps need the SGIN's shares (3.6) and wait until 3.4–3.8 are done: the `cmdkey` line in 4.2, registering the nightly task in 4.5, and the web-arcade check under "Done when".

🔌 OptiPlex Ethernet → your switch (cobra-switch **port 3**, part 2.12) the whole time. Unplug it only if you want Windows setup to skip network sign-in (Rufus's option already handles that).

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

GPU driver: once the RTX 3050 is in (4.7), install NVIDIA's current Game Ready driver. Until then, with the old AMD Oland (R7 250-class, GCN 1) card: current AMD Adrenalin does **not** support it. On amd.com/support, find your card (Graphics → Radeon R7 Series) and install the newest driver listed under **Windows Legacy Drivers**, or let Windows Update install its driver. Don't let AMD's auto-detect tool "upgrade" it to current Adrenalin.

PowerShell **as Admin** (right-click Start → Terminal (Admin)):

```powershell
Rename-Computer cobra-arcade
winget install -e --id Valve.Steam
winget install -e --id Libretro.RetroArch
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
```

PowerShell **not** as Admin (plain Terminal), so the folder and the saved share login below belong to `arcade`, the user Big Box and the nightly copy run as:

```powershell
New-Item -ItemType Directory -Force D:\Roms     # the ROM folder on the 4 TB drive (4.6); does nothing if it exists
Restart-Computer
```

Once the SGIN's Samba shares are up (part 3.6), save the cabinet's login for them. The nightly copy in 4.5 uses it:

```powershell
cmdkey /add:cobra-stream /user:arcade /pass:<samba arcade password>
Test-Path \\cobra-stream\roms        # True = the share answers with that login
```

## 4.3 LaunchBox, Big Box and RetroArch

The cabinet plays everything natively: LaunchBox/Big Box is the menu, RetroArch does the emulating, and the ROMs live on the cabinet's own drive in `D:\Roms`, so games load from a local disk and the cabinet plays even when the SGIN or the network is down. The web arcade (RomM + EmulatorJS on the SGIN, part 3) can't read a disk inside the cabinet, and it has to work while the cabinet is off. So the nightly copy (4.5) sends new and changed ROMs to the SGIN's `roms` share, and RomM picks them up from there. That copy is also the ROMs' second copy, and the vault backup (part 5) covers it.

**Add ROMs on the cabinet, in `D:\Roms\<platform>\`.** The copy only runs cabinet → SGIN, so a ROM uploaded through RomM's web page stays on the SGIN only. A new game shows in Big Box right away, and in the web arcade the morning after (or run the task by hand: `Start-ScheduledTask 'Cobra nightly copy'`, then Scan in RomM).

`D:` stays NTFS, as Windows made it. Nothing in this part formats it.

**ROM folder names.** RomM finds each system by its folder name (`D:\Roms\<platform>\` here, `roms/<platform>/` on the SGIN), using the short names on its "Supported platforms" page: for example `gba`, `gb`, `gbc`, `arcade`, `atari2600`. LaunchBox doesn't care about names. If your folders already have other names, don't rename a big collection: map them instead in RomM's `config.yml` under `system.platforms` (e.g. `"Super Nintendo": snes`).

- [ ] LaunchBox installer from launchbox-app.com → restore the backed-up LaunchBox folder over it (to `D:\LaunchBox` if the WD drive has room, otherwise `C:\LaunchBox`)
- [ ] **Emulator:** Tools → Manage → Emulators → Add → RetroArch → path to `retroarch.exe` (Start menu → right-click RetroArch → Open file location; usually `C:\RetroArch-Win64\`). On the **Associated Platforms** tab, let LaunchBox fill in its default core for each platform, then set Arcade to **FinalBurn Neo** (`fbneo_libretro.dll`) or **MAME 2003-Plus** to match your romset.
- [ ] **Importing games:** Tools → Import → ROM Files → pick `D:\Roms\<platform>` → when asked, choose **use the files in their current location**. The other choice makes a second copy of every ROM inside the LaunchBox folder.
- [ ] Big Box: Options → Startup → start Big Box on Windows startup
- [ ] RetroArch: copy back `saves states system config playlists`. Its own ROM browser can point at `D:\Roms` (Settings → Directory → File Browser), but day to day LaunchBox launches the games.
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

Saves, save states, `.hi` files, the LaunchBox database and the ROMs' main copy live only on the cabinet. Copy them to the SGIN nightly (dock1a's `backups` folder), where the vault backup (part 5) picks them up. One small script does both this and 4.6.

Create the folder with `New-Item -ItemType Directory -Force C:\Cobra`, then save this as `C:\Cobra\nightly-copy.ps1` (Notepad, then "Save as type: All files"):

```powershell
# Nightly copies for cobra-arcade. robocopy /E /XO adds and updates, never deletes.
$log = 'C:\Cobra\nightly-copy.log'
$media = '\\cobra-stream\media'   # the SGIN's drives: wd1, dock1a, dock1b, wd2
$ra = 'C:\RetroArch-Win64'      # your RetroArch folder
$lb = 'D:\LaunchBox'            # or C:\LaunchBox

# 1) cabinet -> SGIN (4.5)
$up = @{
  "$ra\saves"     = "$media\dock1a\backups\arcade\RetroArch\saves"
  "$ra\states"    = "$media\dock1a\backups\arcade\RetroArch\states"
  "$ra\system"    = "$media\dock1a\backups\arcade\RetroArch\system"
  "$ra\config"    = "$media\dock1a\backups\arcade\RetroArch\config"
  "$ra\playlists" = "$media\dock1a\backups\arcade\RetroArch\playlists"
  "$lb\Data"      = "$media\dock1a\backups\arcade\LaunchBox\Data"
  'D:\Roms'       = '\\cobra-stream\roms'        # the web arcade (RomM) reads this copy
}
# 2) SGIN -> D: (4.6). Edit the list: the folders you'd hate to lose, as drive\folder (part 3.4's table).
# Not 'roms': their main copy is already on D: (D:\Roms), and 1) sends them up.
$down = 'dock1a\music', 'dock1a\audiobooks', 'dock1a\books', 'dock1a\comics', 'dock1a\scans', 'dock1a\backups'

Add-Content $log "=== $(Get-Date)"
foreach ($src in $up.Keys) {
  if (Test-Path $src) { robocopy $src $up[$src] /E /XO /R:2 /W:5 /NP /NFL /NDL /LOG+:$log | Out-Null }
}
foreach ($f in $down) {
  robocopy "$media\$f" "D:\Cobra-copy\$f" /E /XO /R:2 /W:5 /NP /NFL /NDL /LOG+:$log | Out-Null
}
```

Register it to run every night (plain PowerShell as `arcade`). Do this once the SGIN's shares are up and `cmdkey` from 4.2 is saved; before that every copy fails:

```powershell
$a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Cobra\nightly-copy.ps1'
$t = New-ScheduledTaskTrigger -Daily -At 3:30am
Register-ScheduledTask -TaskName 'Cobra nightly copy' -Action $a -Trigger $t `
  -Settings (New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12))
Start-ScheduledTask 'Cobra nightly copy'      # first run now; the first pull to D: can take hours
```

- `-StartWhenAvailable`: if the cabinet was off at 3:30, it runs at next boot.
- `/XO` never replaces a file that's newer on the other side, and nothing here deletes. A ROM you delete from `D:\Roms` stays on the SGIN until you remove it there too (`\\cobra-stream\roms`).
- Before the first run, open your RetroArch folder and check that `saves`, `states`, `system`, `config` and `playlists` are there (they appear after RetroArch's first launch). If RetroArch lives somewhere else, change `$ra`.

## 4.6 The OptiPlex's WD drive (4 TB, NTFS)

It stays in the OptiPlex as `D:`, NTFS as Windows made it (if it's the OptiPlex's **only** disk, it's the system disk instead and only job 1 applies), with two jobs:

1. **The cabinet's local game drive.** The ROMs (`D:\Roms`, the main copy; 4.3), Steam library, LaunchBox and its media (box art, videos), so the menu and the games stay fast and don't depend on the network.
2. **An extra copy of what you can't replace, until the vault drive arrives (and after).** The `$down` part of the script in 4.5 pulls those folders into `D:\Cobra-copy` every night. `/E /XO` never deletes, so a file removed by mistake on the SGIN is still here. Check `D:`'s free space against the ROMs plus what you list; movies and TV are the big ones and you can re-rip or re-buy those.

- [ ] Before relying on it: `D:` shows healthy in `Get-PhysicalDisk | Select FriendlyName, HealthStatus` and has no SMART warnings in CrystalDiskInfo


## 4.7 GPU upgrade: RTX 3050 6 GB (modern Mortal Kombat)

The Oland card tops out around PS2-era games. A slot-powered **RTX 3050 6 GB** runs MK11 at 1080p high and MK1 at 1080p low/medium with DLSS, both at their 60 fps cap (estimate, not yet tested on this box).

**Why it fits the 7040 Mini Tower:**

- **Slot:** the PCIe 3.0 x16 slot takes full-height cards, so either version works: Zotac RTX 3050 6GB Solo (full height), or MSI RTX 3050 LP 6G OC / Gigabyte RTX 3050 OC Low Profile 6G (they ship with a full-height bracket too).
- **Power:** the card draws 70 W from the slot and needs no cable. The Mini Tower's 240 W supply covers CPU (65 W) + card + drives with room left.
- **CPU:** the i7-6700 is above MK1's minimum (i5-6600) and below its recommended (i5-8400). With the game capped at 60 fps, that's enough.

⚠️ Buy the **6 GB** model. The RTX 3050 **8 GB** needs an 8-pin power cable the Dell supply doesn't have.

- [ ] Before the swap: download DDU (Display Driver Uninstaller) and the newest NVIDIA Game Ready driver for the RTX 3050 from nvidia.com/drivers onto the cabinet
- [ ] Boot into Safe Mode, run DDU → AMD → Clean and shut down
- [ ] Power off, unplug, swap the Oland for the RTX 3050 in the x16 slot. Plug the monitor into the **card**, not the motherboard's ports.
- [ ] Boot, install the NVIDIA driver (Express). BIOS needs no changes: the card boots fine with UEFI + Secure Boot on.
- [ ] NVIDIA Control Panel → Change resolution → set the monitor's highest refresh rate
- [ ] **Steam library on an SSD.** MK1 and MK11 each need 100 GB or more. If `D:` (the WD drive) is a hard drive, add a Steam library folder on the SSD for these two (Steam → Settings → Storage → Add drive); loading fights from a hard drive is slow.
- [ ] MK1: Settings → Graphics → 1080p, preset Medium, upscaler DLSS Quality. Drop to Low if fights dip below 60.
- [ ] LaunchBox: Tools → Import → Steam Games, so both games show in Big Box. Map the Tankstick in Steam Input (Steam → Settings → Controller) or in each game's controls.

## Done when

- [ ] Power on → Big Box loads by itself → a game from `D:\Roms` plays with the stick
- [ ] After the nightly copy (once the SGIN is up), the same game is in `\\cobra-stream\roms` and shows in the web arcade (`arcade.songofeo.com`) after a RomM library scan
- [ ] Next morning: `C:\Cobra\nightly-copy.log` has no `ERROR` lines
- [ ] After 4.7: MK11 and MK1 launch from Big Box and hold 60 fps in a fight
