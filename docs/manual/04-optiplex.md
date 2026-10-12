# 4. Set up OptiPlex (elysidrome-arcade, Windows 11, 10.10.10.30)

**Result:** the cabinet boots straight into Big Box, ROMs come from the SGIN's `roms` share, and it's patched and activated.

🔌 OptiPlex Ethernet → your switch the whole time. Unplug it only if you want Windows setup to skip network sign-in (Rufus's option already handles that).

## 4.1 Prep

- [ ] Backed up: LaunchBox folder, RetroArch `saves states system config playlists` + `.hi` files, license key (`(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey`)
- [ ] BIOS (F2): latest version, SATA AHCI, UEFI boot, Secure Boot on, TPM (PTT) on, AC Recovery → Power On
- [ ] Windows 11 USB from Rufus with "remove TPM/Secure Boot/RAM requirement" + "remove online account" ticked
- [ ] Boot the stick: **F12** at the Dell logo → UEFI USB
- [ ] Setup: Custom install → delete **every** partition on the internal disk → select the unallocated space → Next
- [ ] Out-of-box: region/keyboard, local account `arcade` with a generated password, all privacy toggles off
- [ ] OPNsense static mapping `.30`

## 4.2 Software and shares

PowerShell (right-click Start → Terminal (Admin)):

```powershell
Rename-Computer elysidrome-arcade
winget install -e --id AMD.Software.Adrenalin            # Oland: if it refuses, use Windows Update driver
winget install -e --id Valve.Steam
winget install -e --id Libretro.RetroArch
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
cmdkey /add:elysidrome-stream /user:arcade /pass:<samba arcade password>
New-SmbMapping -LocalPath R: -RemotePath \\elysidrome-stream\roms -Persistent $true
Restart-Computer
```

## 4.3 Cabinet setup

- [ ] LaunchBox installer from launchbox-app.com → restore backed-up LaunchBox folder over it → Big Box: Options → Startup → start Big Box on Windows startup
- [ ] RetroArch: copy back `saves states system config playlists`; Settings → Directory → set ROMs to `R:\`
- [ ] RetroArch hiscores: Settings → Core → enable MAME hiscore (`hiscore.dat` in `system\mame\`), note the `.hi` path for the hiscore agent later
- [ ] Tankstick: map in RetroArch → Settings → Input → Port 1/2 binds, Save autoconfig
- [ ] Netplay host: Firewall allow TCP 55435 inbound from LAN; OPNsense port forward only if friends join from outside
- [ ] Auto-login: Sysinternals Autologon (`winget install -e --id Microsoft.Sysinternals.Autologon`), user `arcade`
- [ ] Windows Update until nothing left; Settings → Activation shows activated

## Done when

 power on → Big Box loads by itself → a game from `R:\` plays with the stick.
