# 4. Set up OptiPlex (elysidrome-arcade, Windows 11, 10.10.10.30)

**Result:** the cabinet boots straight into Big Box, ROMs come from the SGIN's `roms` share, and it's patched and activated.

🔌 OptiPlex Ethernet → your switch the whole time. Unplug it only if you want Windows setup to skip network sign-in (Rufus's option already handles that).

## 4.1 Prep

- [ ] Backed up: LaunchBox folder, RetroArch `saves states system config playlists` + `.hi` files, license key (`(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey`)
- [ ] BIOS (F2): latest version, SATA AHCI, UEFI boot, Secure Boot on, Security → TPM 2.0 Security on (the 7040 has a discrete TPM, not PTT; if it reports TPM 1.2, flash Dell's TPM 2.0 firmware update first), AC Recovery → Power On
- [ ] Windows 11 USB from Rufus with "remove TPM/Secure Boot/RAM requirement" + "remove online account" ticked
- [ ] Boot the stick: **F12** at the Dell logo → UEFI USB
- [ ] Setup: Custom install → delete **every** partition on the internal disk → select the unallocated space → Next
- [ ] Out-of-box: region/keyboard, local account `arcade` with a generated password, all privacy toggles off
- [ ] OPNsense static mapping `.30`

## 4.2 Software and shares

GPU driver: current AMD Adrenalin does **not** support the Oland (R7 250-class, GCN 1) card. Use the **Windows Legacy Driver** from amd.com/support → Graphics → Radeon R7 Series → your card, or let Windows Update install its driver. ⚠️ Verify the exact legacy version on AMD's page.

PowerShell **as Admin** (right-click Start → Terminal (Admin)):

```powershell
Rename-Computer elysidrome-arcade
winget install -e --id Valve.Steam
winget install -e --id Libretro.RetroArch
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
```

PowerShell **not** as Admin (plain Terminal). A drive mapped from an elevated window is invisible to normal apps like Big Box and RetroArch:

```powershell
cmdkey /add:elysidrome-stream /user:arcade /pass:<samba arcade password>
New-SmbMapping -LocalPath R: -RemotePath \\elysidrome-stream\roms -Persistent $true
Restart-Computer
```

## 4.3 Cabinet setup

- [ ] LaunchBox installer from launchbox-app.com → restore backed-up LaunchBox folder over it → Big Box: Options → Startup → start Big Box on Windows startup
- [ ] RetroArch: copy back `saves states system config playlists`; Settings → Directory → set ROMs to `R:\`
- [ ] RetroArch hiscores are a **per-core** option, not a global setting. Load a game, then Quick Menu → Core Options:
  - **FinalBurn Neo:** "Hiscores" on; needs `hiscore.dat` in `system\fbneo\`
  - **MAME 2003-Plus:** "Hiscores" on (`hiscore.dat` ships with the core's system files in `system\mame2003-plus\`)
  - ⚠️ Verify where each core actually writes `.hi` files (look under `saves\` and `system\` after one game) and note those paths for the hiscore agent
- [ ] Tankstick: map in RetroArch → Settings → Input → Port 1/2 binds, Save autoconfig
- [ ] Netplay host: Firewall allow TCP 55435 inbound from LAN; OPNsense port forward only if friends join from outside
- [ ] Auto-login: Sysinternals Autologon (`winget install -e --id Microsoft.Sysinternals.Autologon`), user `arcade`
- [ ] Windows Update until nothing left; Settings → Activation shows activated

## Done when

 power on → Big Box loads by itself → a game from `R:\` plays with the stick.
