# Elysidrome Build Manual — 01: Stage 0, Prep & Backup

> **Goal:** nothing you care about can be lost, every secret has a home, the domain is on Cloudflare, and every installer is downloaded and checksummed.
> **Time:** 2–3 h of hands-on work, plus up to 24 h waiting for nameservers to change over (start §4 first).
> **Assumes:** you know Windows and Debian administration and networking. Basics are skipped. Every command you need is included.

---

## 0. Order of work

1. §4 Cloudflare nameserver change. Do this first because DNS changeover takes time.
2. §1 Password manager and secrets.
3. §2 Inventory.
4. §3 Backups. **Blocking:** nothing gets wiped until its backup is verified.
5. §5 Xfinity gateway prep.
6. §6 Downloads and USB sticks.
7. §7 Latitude BIOS (only if Proxmox isn't already installed).

---

## 1. Password manager and secrets

Vaultwarden doesn't exist until Stage 4. Until then, keep everything in **Bitwarden (cloud, free)** or **KeePassXC**. Both can be imported into Vaultwarden later. Make a folder called `Elysidrome`.

**Generate secrets.** Don't type them by hand.

On any Windows box (PowerShell 5.1 or 7):

```powershell
# 32 random bytes, base64 (≈44 chars). Uses the OS CSPRNG, not Get-Random.
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)
```

On Linux:

```bash
openssl rand -base64 32
```

Create these entries now. Fill in each one when its stage generates it.

| Entry | Created in |
|---|---|
| Cloudflare account (password + TOTP) | Stage 0 |
| Registrar account (password + TOTP) | Stage 0 |
| Cloudflare API token: `ddns-opnsense` | Stage 0 |
| Cloudflare API token: `acme-gate` | Stage 0 |
| Xfinity gateway admin | Stage 0 |
| Latitude BIOS admin password | Stage 0 |
| Proxmox `root@pam` password + TOTP | Stage 1 |
| Proxmox `eels` (Linux + `eels@pam`) password + TOTP | Stage 1 |
| OPNsense `root` | Stage 2 |
| WireGuard keys | Stage 2 |
| BitLocker recovery keys (each Windows machine) | Stage 0 |

**SSH key.** Make one admin key on your main Windows desktop. OpenSSH client is built into Windows 10/11.

```powershell
ssh-keygen -t ed25519 -C "eels@desktop1"
# Set a passphrase. Key lands in $env:USERPROFILE\.ssh\id_ed25519(.pub)
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub
```

Optional: keep the agent running so you only type the passphrase once per login.

```powershell
# Admin PowerShell
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent
# Normal PowerShell
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

✅ Checkpoint: the password manager has the `Elysidrome` folder, and `id_ed25519.pub` exists.

---

## 2. Inventory

You need the MAC addresses for DHCP reservations in Stage 2. Record them in a note in the password manager or in a spreadsheet.

**Windows machines** (both desktops and the OptiPlex):

```powershell
Get-NetAdapter | Format-Table Name, InterfaceDescription, MacAddress, LinkSpeed, Status
Get-PhysicalDisk | Format-Table FriendlyName, MediaType, HealthStatus, @{n='GB';e={[int]($_.Size/1GB)}}
Get-CimInstance Win32_BIOS | Format-List Manufacturer, SMBIOSBIOSVersion, SerialNumber
```

**Any Linux box, or a Debian live USB** (for example the SGIN, if it isn't running Windows):

```bash
ip -br link
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT
sudo smartctl -a /dev/sdX      # apt install smartmontools; repeat per disk
```

**USB 3 gigabit NIC:** buy one built on a **Realtek RTL8153** (driver `r8152`) or an **ASIX AX88179**. Both drivers are in the Proxmox kernel. You'll find its MAC in Stage 1. Use a **blue USB 3 port** on the Latitude.

**Storage drives that will move to `elysidrome-stream`:** for each one, record its size, its current filesystem, and what's on it. Stage 5 reformats them. **Anything on them must be in §3's backup.**

✅ Checkpoint: you have the MAC of every wired NIC, and a list of every drive with its contents.

---

## 3. Backups

Stage 1 wipes the Latitude. Stage 5 wipes the SGIN and probably the storage drives. Stage 6 wipes the OptiPlex. Back up everything you'd miss to a drive that **isn't being reused in this build**.

### 3.1 BitLocker recovery keys (every Windows machine)

```powershell
# Admin PowerShell
manage-bde -status
manage-bde -protectors -get C:
```

Copy every *Numerical Password* ID and key into the password manager. Firmware and boot-order changes can trigger BitLocker recovery.

### 3.2 Files, with robocopy

Run this for each source folder. `E:` is the backup drive.

```powershell
# /E subdirs  /COPY:DAT data+attrs+timestamps  /DCOPY:DAT  /R:1 /W:1 fast retries
# /XJ skip junctions (avoids AppData loops)  /MT:16 threads  /LOG+ append log
robocopy "C:\Users\eels" "E:\backup\desktop1\Users\eels" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /MT:16 /LOG+:E:\backup\desktop1-robocopy.log /TEE
```

**Verify:** a second dry run should list **zero** files to copy.

```powershell
robocopy "C:\Users\eels" "E:\backup\desktop1\Users\eels" /E /L /XJ /NJH /NDL /NP /FP
# Look at the summary table: Files "Copied" column must be 0.
```

Spot-check a few files by hash:

```powershell
Get-FileHash "C:\Users\eels\Documents\some-important.pdf","E:\backup\desktop1\Users\eels\Documents\some-important.pdf" | Format-Table Hash, Path
```

### 3.3 Things robocopy won't catch

- **Browser data:** sign in to browser sync, or export bookmarks and passwords. Import the passwords into the password manager, then delete the export file.
- **OptiPlex:** game saves, LaunchBox/RetroArch folders, configs, and controller mappings. Copy the whole LaunchBox and RetroArch directories with the robocopy command above.
- **Existing Pi-hole** (if you run one): in the web UI, Settings → Teleporter → Export.
- **Xfinity gateway settings:** take screenshots of port forwards and reservations.
- **Licenses:** Windows product keys or linked Microsoft accounts. Check with `slmgr /dli` in an admin prompt.

### 3.4 Windows 10 deadline

Consumer Windows 10 ESU ends **Oct 13, 2026**. If the OptiPlex still runs Windows 10 after that and you haven't reached Stage 6, unplug it from the network. Run it offline until it's rebuilt.

✅ Checkpoint: every machine has a backup, the robocopy dry runs show 0 files to copy, and the BitLocker keys are stored. **Don't continue until this checkpoint passes.**

---

## 4. Domain on Cloudflare

> Your domain spelling: the overview flags `elysidrome.com` vs `elysidrom.com`. Confirm which one you actually own **before** you add it to Cloudflare.

1. **Secure both accounts.** Turn on TOTP 2FA at the registrar and at Cloudflare. Turn on registrar lock / transfer lock.
2. **Add the domain.** In Cloudflare: *Add a domain* → `elysidrome.com` → **Free** plan. Let it import existing records, then **delete anything you don't recognise**.
3. **Change nameservers.** At the registrar, replace the nameservers with the two Cloudflare gives you. If DNSSEC is on at the registrar, **turn it off first**, then wait. The old DS record breaks resolution once the nameservers change.
4. **Wait until the domain is Active in Cloudflare,** then check:

   ```powershell
   Resolve-DnsName elysidrome.com -Type NS -Server 1.1.1.1
   ```

   ```bash
   dig NS elysidrome.com +short @1.1.1.1
   ```

   ✅ Both return `*.ns.cloudflare.com`.
5. **Turn on DNSSEC** in Cloudflare: *DNS → Settings → Enable DNSSEC*. Paste the DS record it shows into the registrar.
6. **Add CAA records,** so only Let's Encrypt can issue certificates for your domain:

   | Type | Name | Flags | Tag | Value |
   |---|---|---|---|---|
   | CAA | `@` | 0 | `issue` | `letsencrypt.org` |
   | CAA | `@` | 0 | `issuewild` | `letsencrypt.org` |

7. **Don't create A records yet.** Stage 2's DDNS creates and updates them. Every record stays **DNS only (grey cloud)**. The reasons are in overview §4.

### 4.1 API tokens

Make one token per consumer, so you can revoke either one on its own. Go to *My Profile → API Tokens → Create Token → Custom token*:

| Token name | Permissions | Zone resources |
|---|---|---|
| `ddns-opnsense` | Zone · DNS · Edit; Zone · Zone · Read | Include · Specific zone · `elysidrome.com` |
| `acme-gate` | Zone · DNS · Edit; Zone · Zone · Read | Include · Specific zone · `elysidrome.com` |

Leave Client IP filtering empty, since your home IP is dynamic. Store each token in the password manager **immediately**, because Cloudflare shows it only once.

Test each token:

```powershell
curl.exe -s -H "Authorization: Bearer PASTE_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify
```

✅ The response includes `"status":"active"`.

---

## 5. Xfinity gateway prep

Admin UI: `http://10.0.0.1`. Change the admin password if it's still the default.

1. **Confirm you have a real public IPv4, not CGNAT.** You need this to forward 443 and 51820.

   ```powershell
   curl.exe -4 -s https://ifconfig.me
   ```

   Compare the result with the WAN IP on the gateway's *Gateway → Connection → Xfinity Network* page. ✅ They match. If they don't, stop here: you're behind CGNAT and the public-access design needs to change.
2. **Leave room in the DHCP range.** Go to *Gateway → Connection → Local IP Network* and set *DHCP Beginning Address* to `10.0.0.10`. That keeps `10.0.0.2` free for OPNsense's WAN (Stage 2) and `10.0.0.5` free for Proxmox's temporary address (Stage 1).
   ⚠️ Verify: newer XB7/XB8 firmware may move some of these settings into the Xfinity app. Look for them there if the web UI doesn't show them.
3. **Measure upload speed** at a wired desktop with speed.cloudflare.com. Record the result. Stage 5 uses it to size remote streaming.
4. **Don't set up DMZ or port forwards yet.** That happens in Stage 2.

---

## 6. Downloads and USB sticks

Download everything to your desktop and verify the SHA-256 against the value on the vendor's **HTTPS** download page:

```powershell
Get-FileHash .\file.iso -Algorithm SHA256
```

| What | Where | Used in | Media |
|---|---|---|---|
| Proxmox VE **9.x** ISO (latest) | proxmox.com → Downloads | Stage 1 | **USB #1**, written by Rufus in **DD mode** |
| OPNsense **latest** `dvd-amd64` `.iso.bz2` | opnsense.org/download | Stage 2 | None. Stage 1 downloads it straight onto Proxmox |
| Debian **13** netinst amd64 | debian.org/distrib/netinst | Stage 2 (gate VM), Stage 5 (SGIN bare metal) | **USB #2** (Rufus or Ventoy) for the SGIN. Proxmox downloads its own copy |
| Windows 11 ISO + Rufus | microsoft.com/software-download/windows11, rufus.ie | Stage 6 | USB #3. Created in Stage 6 |
| Rufus (portable) | rufus.ie | Stages 1/5/6 | — |

**Write USB #1 (Proxmox):**

1. Open Rufus and select the stick and the Proxmox ISO.
2. Partition scheme **GPT**, target **UEFI**.
3. Click Start. When Rufus asks, choose **"Write in DD Image mode"**. ISO mode produces a stick that doesn't boot.

Don't use Ventoy for Proxmox. The Proxmox installer isn't supported under Ventoy and can fail partway through.

✅ Checkpoint: all hashes match, and USB #1 shows a single partition after writing. Windows may offer to "format" it. **Say no.**

---

## 7. Latitude 5580 BIOS

Press **F2** at the Dell logo for BIOS setup, or **F12** for the one-time boot menu. Skip this section if Proxmox is already installed and boots fine. Still check items 2, 4 and 5 below the next time you reboot.

| Setting | Path (Dell BIOS) | Value | Why |
|---|---|---|---|
| Admin password | Security → Admin Password | Set it, and store it | Prevents someone at the console from changing boot settings |
| SATA operation | System Configuration → SATA Operation | **AHCI** (not RAID On) | With RAID On / Intel RST, the Linux installer may not see the NVMe |
| Virtualization | Virtualization Support | Enable **VT** and **VT-d** | KVM needs VT. VT-d is for passthrough later |
| AC behaviour | Power Management → AC Behavior | **Wake on AC** | After a power cut that drains the battery, it turns back on by itself |
| Battery charging | Power Management → Primary Battery Charge Configuration | **Custom: start 75 %, stop 90 %** | It's plugged in 24/7. Saves battery wear but keeps most of the UPS runtime. ⚠️ Verify the exact option names on your BIOS revision |
| Wireless | Wireless → Wireless Device Enable | Turn **off** WLAN and Bluetooth | A firewall host shouldn't have radios |
| Secure Boot | Secure Boot | Leave **enabled** | Proxmox VE 8.1+ boots with Secure Boot on |
| Boot | Boot Sequence | UEFI, USB first only while installing | — |

**Update the BIOS first** if Dell has a newer version: dell.com/support → service tag → Drivers → BIOS. Run the `.exe` from the old Windows install before you wipe it, or from a FreeDOS USB. Install BIOS updates while Windows is still there.

---

## Stage 0 done when

- [ ] Backups verified (§3 checkpoint)
- [ ] Domain is Active on Cloudflare, DNSSEC and CAA set, two tokens verified
- [ ] Public IPv4 confirmed (not CGNAT), Xfinity DHCP starts at `.10`
- [ ] ISOs verified, Proxmox USB written in DD mode
- [ ] MACs recorded, USB NIC in hand
- [ ] Latitude BIOS set

**Next:** `02-stage1-proxmox-command-center.md`.
