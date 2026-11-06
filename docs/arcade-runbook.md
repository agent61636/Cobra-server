# Arcade runbook: RomM web arcade + cobra-arcade cabinet

Run top to bottom. One command per block. Each step names the machine, the window and the prompt you should see.

Files (project Library, or `scripts/arcade/build-bundles.sh`): **`arcade-sgin.tar.gz`** and **`arcade-cabinet.zip`**. Download both on **the-box** into `Downloads`.

The gate needs nothing: `arcade.songofeo.com` already points at `10.6.9.20:8080`.

---

## 1. SGIN check (the-box)

**the-box → Windows Terminal → PowerShell tab** (`PS C:\Users\...>`):

```powershell
scp $HOME\Downloads\arcade-sgin.tar.gz eels@10.6.9.20:/tmp/
```

**the-box → Windows Terminal → new tab:**

```powershell
ssh eels@10.6.9.20
```

Prompt: `eels@cobra-stream:~$`

```bash
tar -xzf /tmp/arcade-sgin.tar.gz -C /tmp
```

```bash
bash /tmp/cobra-arcade/check.sh
```

Ends with `ALL GOOD.` Any `FAIL` line prints its own fix. Paste the output to Claude if unsure.

---

## 2. Cabinet: scripts in place (at the OptiPlex)

**the-box → PowerShell tab** (`PS C:\Users\...>`):

```powershell
New-Item -ItemType Directory -Force \\cobra-stream\media\dock1a\backups\arcade\setup
```

```powershell
Copy-Item $HOME\Downloads\arcade-cabinet.zip \\cobra-stream\media\dock1a\backups\arcade\setup\
```

**OptiPlex, logged in as `arcade` → Terminal (not admin)** (`PS C:\Users\arcade>`). It asks for the Samba `arcade` password:

```powershell
cmdkey /add:cobra-stream /user:arcade /pass
```

```powershell
New-Item -ItemType Directory -Force C:\Cobra\setup
```

```powershell
Expand-Archive \\cobra-stream\media\dock1a\backups\arcade\setup\arcade-cabinet.zip C:\Cobra\setup -Force
```

```powershell
Get-ChildItem C:\Cobra\setup | Unblock-File
```

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\00-status.ps1
```

Read-only report: every `TODO` line is what's left. Paste it to Claude.

---

## 3. Cabinet: base setup

**OptiPlex → Start → right-click Terminal → Run as administrator** (`PS C:\WINDOWS\system32>`):

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\01-base.ps1
```

Autologon opens if needed: Username `arcade`, Domain `cobra-arcade`, the password, **Enable**. If it ends with "Reboot needed":

```powershell
Restart-Computer
```

---

## 4. Cabinet: ROM folder map for RomM

**OptiPlex → Terminal (not admin)** (`PS C:\Users\arcade>`):

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\03-roms-map.ps1
```

Renames nothing. `TODO` folders: tell Claude their names.

---

## 5. SGIN: start RomM (the-box)

**the-box → SSH tab** (`eels@cobra-stream:~$`):

```bash
sudo machinectl shell podsvc@
```

Prompt: `podsvc@cobra-stream:~$`

```bash
bash /tmp/cobra-arcade/romm-up.sh
```

Ends with `RomM is up`. If it says the cabinet's folder map isn't in config.yml yet:

```bash
bash /tmp/cobra-arcade/romm-platforms.sh
```

```bash
exit
```

Back at `eels@cobra-stream:~$`.

**the-box → browser:** `http://10.6.9.20:8080` → setup wizard → admin user `eels`, password saved in Vaultwarden. Then `https://arcade.songofeo.com` opens RomM (no sign-in at home).

---

## 6. Cabinet: nightly copy, first run now

**OptiPlex → Terminal (not admin)** (`PS C:\Users\arcade>`):

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\02-nightly.ps1 -RunNow
```

It stops by itself if `D:\Roms` is bigger than dock1b's free space. Watch the copy:

```powershell
Get-Content C:\Cobra\nightly-copy.log -Tail 20 -Wait
```

`Ctrl+C` stops watching (not the copy). When `=== end` shows: **the-box browser → RomM → Library → Scan**.

---

## 7. Cabinet: LaunchBox / Big Box (GUI, on the OptiPlex)

- [ ] LaunchBox installer (launchbox-app.com) → `D:\LaunchBox`. Backed-up LaunchBox folder? Copy it over the install.
- [ ] Tools → Manage → Emulators → Add → RetroArch → path from `00-status.ps1` → Associated Platforms: defaults, Arcade = FinalBurn Neo (or MAME 2003-Plus to match the romset)
- [ ] Tools → Import → ROM Files → `D:\Roms\<platform>` → **use the files in their current location**
- [ ] Options → Startup → start Big Box on Windows startup
- [ ] Options → Controllers → map the Tankstick
- [ ] RetroArch → Settings → Input → Port 1 / Port 2 binds → Save autoconfig

---

## 8. Cabinet: LED-Wiz

- [ ] LEDBlinky (ledblinky.net) installed to `C:\LEDBlinky`

**OptiPlex → Terminal (not admin)**, LaunchBox closed:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\04-ledwiz-test.ps1
```

At each port type what lit (`P1 B1 red`), Enter = nothing, `r` = again, `q` = stop. Saved to `C:\Cobra\ledwiz-portmap.csv`. Then manual 11.3 to 11.5 with that file open: `GenLEDBlinkyInputMap.exe`, `LEDBlinkyConfig.exe` (FE = LaunchBox), LaunchBox → Tools → Options → LEDBlinky.

---

## 9. Cabinet: marquee, Pinball FX, RetroArch display

- [ ] Marquee monitor plugged in, Settings → System → Display → Extend, dragged **above** screen 1

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\05-displays.ps1
```

It prints the Big Box marquee screen and the exact Pinball FX Backglass/Dotmatrix numbers. Enter them as printed.

RetroArch closed:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\06-retroarch.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\06-retroarch.ps1 -Apply
```

`-Apply` backs up `retroarch.cfg` first.

---

## 10. Done check

**OptiPlex:**

```powershell
powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\00-status.ps1
```

**Phone on cellular (Wi-Fi off):** `https://arcade.songofeo.com` → gate sign-in → RomM → one game plays in the browser.
