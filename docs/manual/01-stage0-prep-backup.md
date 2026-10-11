# Elysidrome Build Manual — 01: Stage 0, Prep & Backup

> **Goal:** nothing gets wiped until it's backed up and the backup is proven. By the end of this stage you have an inventory of every box, verified backups, `elysidrome.com` on Cloudflare with API tokens ready, the USB NIC in hand, and bootable USB sticks for every installer.
>
> **Time:** 2–3 h of hands-on work, plus however long the copies and the nameserver change take.
> **Nothing in this stage changes how the house gets online.** Family internet keeps working the whole time.

---

## 0. What you need

| Item | Notes |
|---|---|
| External drive with enough free space for everything you back up | Must **not** be a drive that a later stage formats (see §3.4). |
| 3 USB sticks, 8 GB or larger | One each for Proxmox, Debian and Windows 11. Contents get erased. |
| USB 3 gigabit NIC | Order it now (§5). Stage 1 can't finish without it. |
| A Windows 11 desktop | Your admin workstation for every stage. Everything in this stage runs there unless it says otherwise. |
| Your registrar login (if you already own the domain) and a Cloudflare account | Free plan is enough. |

---

## 1. Interim password manager

Every later stage generates secrets and tells you to store them immediately. Vaultwarden (`vault.elysidrome.com`) doesn't exist until Stage 4, so start with **KeePassXC**, a local, offline password manager. You'll import its database into Vaultwarden in Stage 4.

On the Windows desktop (PowerShell, as your normal user):

```powershell
winget install --id KeePassXCTeam.KeePassXC -e
```

1. Open KeePassXC → **Create new database** → name it `elysidrome.kdbx`, save it under `Documents\Elysidrome\`.
2. Use a long passphrase you can type from memory (KeePassXC's generator → **Passphrase** tab, 6+ words). Write it on paper and keep the paper somewhere physical and safe.
3. Create a group called `Elysidrome` with subgroups `Hosts`, `Cloudflare`, `ISP`, `Apps`.

How secrets get generated in this manual:

```powershell
# Windows: 32 random bytes as base64 (works in Windows PowerShell 5.1 and PowerShell 7)
$b = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
[Convert]::ToBase64String($b)
```

```bash
# Linux equivalent, used from Stage 1 on
openssl rand -base64 32
```

For passwords you'll have to type at a console (installer root passwords, BIOS passwords), use KeePassXC's generator with ~20 characters, letters + digits only, so you don't fight keyboard layouts on a bare console.

✅ Checkpoint: `elysidrome.kdbx` exists, opens with your passphrase, and a copy is on the external drive.

---

## 2. Inventory

Fill this table in now; Stage 2 (DHCP reservations) and Stage 7 (runbooks) reuse it. Save it as `Documents\Elysidrome\inventory.md` (or a KeePassXC note).

| Host (target name) | Hardware | Service tag / serial | Onboard NIC MAC | Current OS | Windows license | BIOS version | Gets wiped? |
|---|---|---|---|---|---|---|---|
| command-center | Latitude 5580 | | | | | | **Yes** (Stage 1) |
| elysidrome-stream | SGIN X15 | | | | | | **Yes** (Stage 5) |
| elysidrome-arcade | OptiPlex 7040 | | | | | | **Yes** (Stage 6) |
| desktop 1 (→ .50) | | | | Windows 11 | | | No |
| desktop 2 (→ .51) | | | | Windows 11 | | | No |
| R620 | | | | | — | | Later |
| USB 3 NIC (WAN) | | — | | — | — | — | — |

Commands to fill it in.

On each Windows machine (PowerShell):

```powershell
# Model, serial/service tag, BIOS version
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model
Get-CimInstance Win32_BIOS | Select-Object SerialNumber, SMBIOSBIOSVersion, ReleaseDate

# NICs and MAC addresses (note the wired one)
Get-NetAdapter | Format-Table Name, InterfaceDescription, MacAddress, LinkSpeed, Status

# Windows edition and license state
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version
cscript //nologo $env:windir\System32\slmgr.vbs /dli
# OEM key embedded in the BIOS (blank on many machines; that's fine)
(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
```

On any machine currently running Linux (as a sudo user):

```bash
sudo dmidecode -s system-manufacturer; sudo dmidecode -s system-product-name
sudo dmidecode -s system-serial-number; sudo dmidecode -s bios-version
ip -br link          # MAC addresses
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL
```

**Windows licenses.** Windows 10/11 activation is usually a *digital license* tied to the hardware. Check **Settings → System → Activation** on the OptiPlex and confirm it says it's linked to your Microsoft account. If it is, the Windows 11 install in Stage 6 reactivates on its own. Store any product key you find in KeePassXC (`Hosts/elysidrome-arcade`).

### 2.1 Storage drives

List every drive that will end up attached to `elysidrome-stream` (Stage 5 decides how they're formatted and mounted; **don't reformat anything now**).

| Drive | Size | Connection | Current filesystem | Used | Holds data that must survive? | Planned label (`/srv/storage/<label>`) |
|---|---|---|---|---|---|---|
| | | USB / SATA | NTFS / exFAT / ext4 | | | e.g. `media1` |

On Windows:

```powershell
Get-Volume | Where-Object DriveLetter | Format-Table DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}
Get-PhysicalDisk | Format-Table FriendlyName, MediaType, BusType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, HealthStatus
```

✅ Checkpoint: every row in both tables is filled in.

---

## 3. Back up every machine that gets wiped

Three machines get wiped: the **Latitude** (Stage 1), the **SGIN** (Stage 5) and the **OptiPlex** (Stage 6). Back up all three now, even the ones wiped later. It's one sitting instead of three, and you won't be tempted to skip it mid-build.

Layout on the external drive (assume it's `E:`):

```
E:\backup\
   command-center\     (Latitude)
   elysidrome-stream\  (SGIN)
   elysidrome-arcade\  (OptiPlex)
```

### 3.1 What to capture from each Windows machine

Run on the machine being backed up (PowerShell **as Administrator**, external drive plugged into that machine). Set `$H` to the target hostname first.

```powershell
$H = 'elysidrome-arcade'          # or command-center / elysidrome-stream
$D = "E:\backup\$H"
New-Item -ItemType Directory -Force $D | Out-Null

# 1. Installed apps (reinstall list)
winget export -o "$D\winget-apps.json" --include-versions
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
                 HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher |
  Sort-Object DisplayName | Export-Csv "$D\installed-programs.csv" -NoTypeInformation

# 2. Wi-Fi profiles, including keys (treat this folder as a secret)
New-Item -ItemType Directory -Force "$D\wifi" | Out-Null
netsh wlan export profile key=clear folder="$D\wifi"

# 3. BitLocker recovery keys, if BitLocker is on (copy them into KeePassXC too)
manage-bde -status
manage-bde -protectors -get C: > "$D\bitlocker-C.txt"

# 4. Hardware/driver report, handy if something misbehaves after the reinstall
Get-PnpDevice -PresentOnly | Sort-Object Class, FriendlyName |
  Select-Object Class, FriendlyName, InstanceId | Export-Csv "$D\devices.csv" -NoTypeInformation
```

Then copy user data. `/XJ` skips the junction points inside user profiles that otherwise make robocopy loop forever.

```powershell
# One line per profile you care about
robocopy "C:\Users\<name>" "$D\Users\<name>" /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:16 `
  /XD "AppData\Local\Temp" "AppData\Local\Microsoft\Windows\INetCache" `
  /LOG:"$D\robocopy-<name>.log" /TEE
```

Robocopy exit codes **0–7 are success**, 8+ means some files failed. Check with `echo $LASTEXITCODE`, then search the log for `ERROR`.

**Also copy anything outside the profile that you'd miss.** The usual suspects:

| Machine | Look for |
|---|---|
| OptiPlex (arcade) | The whole LaunchBox folder (games, images, `Data\`, emulators), RetroArch folder (`saves\`, `states\`, `system\` BIOS files, `hiscore`/`.hi` files, `config\`, `playlists\`), Steam `steamapps\common` only for games with local-only saves, X-Arcade/key-mapper configs |
| Latitude | Anything in `C:\` outside `Users`, browser data if not synced |
| SGIN | Media folders, anything it currently serves |

```powershell
# Example: LaunchBox in its usual location; adjust paths to what Get-ChildItem shows
robocopy "C:\Users\<name>\LaunchBox" "$D\LaunchBox" /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:16 /LOG:"$D\robocopy-launchbox.log" /TEE
```

**Browsers:** the easiest path is to turn on sync (Edge/Chrome/Firefox account) and confirm on another machine that bookmarks and passwords arrived. Then import those passwords into KeePassXC (Stage 4 moves them into Vaultwarden).

### 3.2 If a machine runs Linux today

As a sudo user, external drive mounted at `/mnt/backup`:

```bash
H=elysidrome-stream
sudo mkdir -p /mnt/backup/$H
sudo rsync -aHAX --info=progress2 /home/ /mnt/backup/$H/home/
sudo rsync -aHAX /etc/ /mnt/backup/$H/etc/
dpkg --get-selections > /tmp/packages.txt && sudo cp /tmp/packages.txt /mnt/backup/$H/
# plus any data directories it serves, e.g. /srv
```

If the external drive is NTFS/exFAT, `-AX` (ACLs/xattrs) won't stick. Use `-rlt` instead of `-aHAX` for user data, and tar `/etc` so ownership survives: `sudo tar czf /mnt/backup/$H/etc.tgz /etc`.

### 3.3 Prove the backup

A backup you haven't checked is a hope. Do both checks for every robocopy job.

**Check 1: robocopy finds nothing left to copy.** Re-run the same command with `/L` (list only). The summary table's **Copied** column must show `0` for Files (Mismatch and FAILED must be 0 too; Extras is fine).

```powershell
robocopy "C:\Users\<name>" "$D\Users\<name>" /E /XJ /L /NJH /NFL /NDL `
  /XD "AppData\Local\Temp" "AppData\Local\Microsoft\Windows\INetCache"
```

**Check 2: hash a random sample.** Check 1 compares size and timestamp. This compares contents.

```powershell
$src = "C:\Users\<name>"; $dst = "$D\Users\<name>"
Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object FullName -notmatch '\\AppData\\' | Get-Random -Count 25 | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length)
    $a = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    $b = (Get-FileHash -LiteralPath ($dst + $rel) -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    '{0}  {1}' -f $(if ($a -and $a -eq $b) {'OK  '} else {'DIFF'}), $rel
  }
```

Linux equivalent (no output = identical, checks every file's contents):

```bash
sudo rsync -aHAXn --checksum --itemize-changes /home/ /mnt/backup/$H/home/
```

**Check 3: open a few files** from the backup on a *different* machine: a photo, a document, a LaunchBox `Data\*.xml`. Proves the drive reads elsewhere.

✅ Checkpoint: every job shows exit code < 8, `Copied = 0` on the `/L` re-run, 25/25 `OK`, and spot-opened files work on another computer. Mark each machine "backed up ✔" in the inventory.

### 3.4 Rules for the backup drive

- **Irreplaceable files (photos, documents, the RetroArch saves and `.hi` files) need a second copy** somewhere that isn't this drive: OneDrive or another disk. One copy is not a backup.
- If this external drive is also one of the storage drives that will attach to `elysidrome-stream`, mark it **"do not format"** in §2.1. Stage 5 mounts it as-is or copies off it before formatting.
- Unplug it and put it away once all three checks pass. It stays offline until Stage 5.

---

## 4. Firmware updates while Windows is still on the boxes

Dell's BIOS updaters run easiest from Windows, so do it now, before the wipes.

1. On each Dell (Latitude 5580, OptiPlex 7040): go to `https://www.dell.com/support`, enter the service tag from §2, open **Drivers & Downloads**, category **BIOS**, download the newest and run it. Or install Dell Command | Update and let it apply only the BIOS:
   ```powershell
   winget install --id Dell.CommandUpdate -e
   ```
2. **Keep the Latitude on AC power** during its flash, with the battery above 10% (the updater refuses otherwise).
3. If BitLocker is on, the updater suspends it for one reboot. That's expected.
4. The SGIN (generic mini PC) rarely gets BIOS updates. Check the vendor's support page and skip it if there's nothing.

✅ Checkpoint: the BIOS version column in §2 shows the new version for both Dells (re-run the `Win32_BIOS` command).

BIOS *settings* (virtualization, AHCI, power-on behavior) are changed in Stage 1 for the Latitude and Stages 5/6 for the others.

---

## 5. Buy the USB 3 gigabit NIC

This is the only required purchase. It becomes the **WAN** port of `command-center` (Proxmox bridge `vmbr1`, cabled to the Xfinity gateway).

- **Buy one with a Realtek RTL8153 chipset.** Linux supports it out of the box (`r8152` driver, in every Proxmox kernel), and it's the most common chip in $12–15 adapters. ASIX AX88179 also works, but some cheap AX88179 clones misbehave under load.
- USB-A, gigabit, wired. Skip hubs/docks with built-in NICs. More chips, more to go wrong.
- ⚠️ Verify: the listing or box names the chipset. "TP-Link UE300" is commonly sold as RTL8153, but check the listing before you buy.

Record its MAC in the inventory when it arrives (it's printed on the label, or plug it into Windows and run `Get-NetAdapter`).

---

## 6. ISP side: Xfinity gateway facts

Stage 2 puts OPNsense behind the Xfinity gateway (router mode, DMZ host → `10.0.0.2`). Collect what it needs now.

1. Log in to the gateway at `http://10.0.0.1` (or the Xfinity app; newer xFi gateways only offer some settings there). Store the admin password in KeePassXC (`ISP/xfinity-gateway`). If it's still the default, change it now to a generated one.
2. Write down: gateway model, current LAN range (**should be 10.0.0.0/24**, see overview §3), DHCP pool, existing port forwards, whether it offers **DMZ host** and **reserved IP / DHCP reservation**, and whether IPv6 is on.
3. **Check for CGNAT.** Public hosting only works if the gateway's WAN address is your real public IP.
   ```powershell
   (Invoke-RestMethod https://api.ipify.org)
   ```
   Compare with the WAN/Internet IPv4 shown on the gateway's status page. **They must match**, and it must not start with `100.64`–`100.127` (that's carrier-grade NAT). If they don't match, stop and call Xfinity before Stage 2.
4. **Speed test** (wired, `https://speed.cloudflare.com`). Record download and **upload**. Upload is your remote-streaming ceiling (overview §5).

✅ Checkpoint: the gateway password is in KeePassXC, public IP matches the gateway's WAN IP, upload speed recorded.

---

## 7. Domain on Cloudflare

### 7.1 Put the zone on Cloudflare

**If you don't own the domain yet:** buy it through Cloudflare Registrar (Cloudflare dashboard → **Domain Registration → Register Domains**). It's sold at cost, and the zone is set up for you; skip to §7.2.

**If it's registered somewhere else:**

1. **At the old registrar, turn DNSSEC off first** if it's on. Changing nameservers with stale DNSSEC records breaks the whole domain for up to a couple of days.
2. Cloudflare dashboard → **Add a domain** → enter `elysidrome.com` → **Free** plan. Let it scan existing records. Delete anything you don't recognize.
3. Cloudflare shows two nameservers (`xxx.ns.cloudflare.com`). At the registrar, replace the nameservers with exactly those two.
4. Wait for Cloudflare to email "active" (minutes to a few hours). Check from Windows:
   ```powershell
   Resolve-DnsName elysidrome.com -Type NS -Server 1.1.1.1
   ```
5. Once active: Cloudflare → **DNS → Settings → DNSSEC → Enable**, copy the DS record into the registrar.

✅ Checkpoint: `Resolve-DnsName ... -Type NS` returns the two `*.ns.cloudflare.com` servers, and the dashboard shows the zone **Active**.

### 7.2 Record plan (don't create the app records yet)

Nothing points at your house until OPNsense is guarding it, so **no app records get created in Stage 0**. This is the plan Stage 2 (DDNS) and later stages follow:

| Name | Type | Target | Proxy status | Created in |
|---|---|---|---|---|
| `elysidrome.com` (apex) | A | your home IP, kept current by OPNsense DDNS | **DNS only (grey)** | Stage 2 |
| `tv`, `books`, `comics`, `eelsmusic`, `rupaulradio`, `docs`, `metube`, `arcade`, `home`, `status` | CNAME | `elysidrome.com` | **DNS only (grey)** | Stage 4, as each app goes live |
| `scores` | CNAME | `elysidrome.com` | DNS only | Hiscore stage (reserved, overview §8) |
| `radio` | CNAME | `elysidrome.com` | DNS only | Stage 8 |
| `vault` | **none** | | | Never public. Pi-hole answers it on the LAN/VPN only. |

Why CNAMEs to the apex: DDNS then has to update one record, not a dozen.

**Cloudflare turns new A/CNAME records orange (proxied) by default.** Every time you add one, click the cloud to grey before saving. Orange would put video through Cloudflare's proxy, which its terms restrict (overview §4).

### 7.3 API tokens

Two least-privilege tokens, one per consumer, so either can be revoked alone.

Cloudflare → profile icon → **My Profile → API Tokens → Create Token → "Edit zone DNS" template**:

| Token name | Permissions | Zone resources | Used by |
|---|---|---|---|
| `opnsense-ddns` | Zone · DNS · Edit **and** Zone · Zone · Read | Include · Specific zone · `elysidrome.com` | OPNsense DDNS (Stage 2) |
| `gate-acme` | Zone · DNS · Edit **and** Zone · Zone · Read | Include · Specific zone · `elysidrome.com` | Wildcard certificate DNS-01 challenge on the gate (Stage 4) |

The token is shown **once**. Paste it straight into KeePassXC (`Cloudflare/opnsense-ddns`, `Cloudflare/gate-acme`).

Verify each token (PowerShell; paste the token when prompted):

```powershell
$t = Read-Host 'Token' -AsSecureString
$tok = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($t))
Invoke-RestMethod https://api.cloudflare.com/client/v4/user/tokens/verify -Headers @{Authorization = "Bearer $tok"}
Remove-Variable tok, t
```

✅ Checkpoint: both return `status : active` and `success : True`.

---

## 8. Installers and USB sticks

### 8.1 Download and verify

Make `Documents\Elysidrome\iso\` and download into it:

| Installer | Where | Used in | Goes on |
|---|---|---|---|
| **Proxmox VE 9.x** ISO (latest) | `https://www.proxmox.com/en/downloads` → Proxmox VE → ISO Installer | Stage 1 | USB stick #1 |
| **Debian 13** netinst, amd64 | `https://www.debian.org/distrib/netinst` (file `debian-13.x.y-amd64-netinst.iso`) | Stage 5 (SGIN, bare metal) | USB stick #2 |
| **Windows 11** ISO, x64 | `https://www.microsoft.com/software-download/windows11` → "Download Windows 11 Disk Image (ISO)" | Stage 6 | USB stick #3 |
| **OPNsense** (latest), `amd64`, image type **dvd** | `https://opnsense.org/download/` | Stage 2 | **No stick.** It's uploaded into Proxmox in Stage 1. |

The Debian ISO for the `elysidrome-gate` VM and the OPNsense ISO are fetched straight onto Proxmox in Stage 1, so you don't have to carry them over. Downloading them here too is harmless and gives you a known-good copy.

OPNsense downloads as `.iso.bz2`. Decompress it with 7-Zip (`winget install --id 7zip.7zip -e`, then right-click → 7-Zip → Extract Here).

**Verify every download** against the SHA256 published next to it (Proxmox: on the download page; Debian: `SHA256SUMS` in the same folder; OPNsense: the `*-checksums-amd64.sha256` file on the mirror; Microsoft: listed under the download button):

```powershell
cd $HOME\Documents\Elysidrome\iso
$expected = '<paste the published SHA256>'
(Get-FileHash .\proxmox-ve_9.x-y.iso -Algorithm SHA256).Hash -eq $expected   # must print True
```

For OPNsense, hash the **`.bz2` file** if the published checksum is for the `.bz2`, or the `.iso` if it's for the `.iso`. The checksum file names which.

✅ Checkpoint: `True` for every file.

### 8.2 Write the sticks

Install Rufus: `winget install --id Akeo.Rufus -e`.

| Stick | Rufus settings |
|---|---|
| #1 Proxmox | Select the Proxmox ISO → Partition scheme **GPT**, target **UEFI** → Start → when asked, choose **"Write in DD Image mode"**. (Proxmox's installer only boots reliably from a raw copy.) |
| #2 Debian | Debian ISO → GPT/UEFI → Start → **DD Image mode** as well. |
| #3 Windows 11 | Windows ISO → GPT/UEFI → Start → in the **Windows User Experience** dialog, tick *Remove requirement for 4GB+ RAM, Secure Boot and TPM 2.0*, and *Remove requirement for an online Microsoft account*. Leave the local-account box empty; Stage 6 sets up the cabinet's accounts. (The i7-6700 isn't on Microsoft's supported CPU list; overview #2 explains why that's fine.) |

Label each stick with a marker or tape.

✅ Checkpoint: three labeled sticks. Optional quick test: boot the Latitude from stick #1 (F12 at the Dell logo → pick the USB) and confirm the Proxmox installer menu appears, then power off without installing.

---

## 9. Plan the cutover

Stage 1 doesn't touch the house network. **Stage 2 does**: it moves everything wired behind OPNsense, and there'll be a stretch with no internet on wired devices.

- Pick a 3–4 h window for Stage 2 when nobody needs the internet. Tell the household.
- The Xfinity Wi-Fi keeps working throughout. Phones on Wi-Fi can read this manual while the wired side is down.
- Print or save offline (PDF) the Stage 1 and Stage 2 guides.
- Cabling for Stage 2: two Ethernet cables at the Latitude (USB NIC → Xfinity gateway; onboard port → your switch). Have them ready.

---

## 10. Stage 0 exit checklist

- [ ] KeePassXC database created, passphrase on paper, copy on the external drive
- [ ] Inventory (§2) and storage-drive table (§2.1) filled in
- [ ] Latitude, SGIN and OptiPlex backed up, all three verification checks passed, irreplaceable files have a second copy
- [ ] Both Dell BIOSes updated
- [ ] USB 3 NIC (RTL8153) in hand, MAC recorded
- [ ] Xfinity admin password stored, no CGNAT, upload speed recorded
- [ ] Zone **Active** on Cloudflare; DNSSEC on
- [ ] `opnsense-ddns` and `gate-acme` tokens verified and stored
- [ ] Proxmox, Debian and Windows 11 sticks written from verified ISOs; OPNsense ISO verified
- [ ] Stage 2 window agreed with the household

Next: **[Stage 1 — Proxmox on command-center](02-stage1-proxmox-command-center.md)**.
