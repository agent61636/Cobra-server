# 4. Set up OptiPlex (elysidrome-arcade, Windows 11, 10.10.10.30)

- [ ] Backed up: LaunchBox folder, RetroArch `saves states system config playlists` + `.hi` files, license key (`(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey`)
- [ ] BIOS (F2): latest version, SATA AHCI, UEFI boot, Secure Boot on, TPM (PTT) on, AC Recovery → Power On
- [ ] Windows 11 USB from Rufus with "remove TPM/Secure Boot/RAM requirement" + "remove online account" ticked
- [ ] Install: delete all partitions, local account `arcade`
- [ ] OPNsense static mapping `.30`

PowerShell (Admin):

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

- [ ] LaunchBox installer from launchbox-app.com → restore backed-up LaunchBox folder over it → Big Box: Options → Startup → start Big Box on Windows startup
- [ ] RetroArch: copy back `saves states system config playlists`; Settings → Directory → set ROMs to `R:\`
- [ ] RetroArch hiscores: Settings → Core → enable MAME hiscore (`hiscore.dat` in `system\mame\`), note the `.hi` path for the hiscore agent later
- [ ] Tankstick: map in RetroArch → Settings → Input → Port 1/2 binds, Save autoconfig
- [ ] Netplay host: Firewall allow TCP 55435 inbound from LAN; OPNsense port forward only if friends join from outside
- [ ] Auto-login: Sysinternals Autologon (`winget install -e --id Microsoft.Sysinternals.Autologon`), user `arcade`
- [ ] Windows Update until nothing left; Settings → Activation shows activated

Done when: power on → Big Box loads by itself → a game from `R:\` plays with the stick.
