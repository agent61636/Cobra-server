# 0. Before you start

**Result:** nothing you care about can be lost, the domain is ready on Porkbun, and every number the later parts ask for is written down in one place.

Doing part 1 already (Proxmox on the Latitude)? That's fine. Nothing here touches the Latitude; just finish this list before part 2's cutover.

## 0.1 A safe place for secrets

Every part generates passwords and keys "into your password manager". Vaultwarden doesn't exist until part 5, so use an interim one now:

- [ ] Install **KeePassXC** on your Windows desktop (`winget install -e --id KeePassXCTeam.KeePassXC`), create `cobra.kdbx` with a strong master password, and copy it to a USB stick after each session
- [ ] Part 5 moves it into Vaultwarden: KeePassXC → Database → Export → **CSV**, then Vaultwarden → Tools → Import data → format **KeePassX (csv)**. Delete the CSV file right after; it holds every password in plain text.

## 0.2 Inventory (fill in as you go)

Copy this table into KeePassXC as a note, or keep it on paper next to the machines.

| What | Where to find it | Value |
|---|---|---|
| Latitude onboard NIC name and MAC | Proxmox shell: `ip -br link` (Proxmox 9 calls it `nic0`) | |
| Latitude USB NIC name and MAC | same (`enx…` followed by its MAC) | |
| SGIN (old server) MAC and current IP | Xfinity app → Connected devices. The SGIN has no built-in Ethernet, so this is its USB adapter's MAC (`enx…` on the SGIN) | |
| OptiPlex MAC | `ipconfig /all` on it | |
| the-box / the-spire MACs (Ethernet) | `ipconfig /all` | |
| Cobra1 laptop MAC (**Wi-Fi** adapter) | `ipconfig /all` → "Wireless LAN adapter Wi-Fi" | |
| Every port forward on Xfinity today | Xfinity app → Advanced → Port forwarding | |
| What the old server runs, and on which ports | `podman ps` / `docker ps` on the SGIN | |
| Current public IPv4 | `curl -4 https://ifconfig.me` | |
| Windows key (OptiPlex) | `(Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey` | |

## 0.3 Backups before anything is wiped

| Machine | Wiped in | Copy off first |
|---|---|---|
| SGIN (old server) | Part 3 | App configs and databases, compose/Quadlet files, anything on its internal disk. The USB drives are not wiped. |
| OptiPlex | Part 4 | LaunchBox folder, RetroArch `saves states system config playlists`, every `.hi` file, game saves outside RetroArch |
| Latitude | Part 1 (done) | — |

- [ ] Put the copies on a drive that is **not** one of the SGIN's USB drives (a desktop's disk or the OptiPlex's WD drive), so one failure can't take both the original and the copy
- [ ] Open one or two files from each copy, to make sure the copy is real

### BitLocker recovery keys (every Windows machine)

BIOS updates, boot-order changes and swapping a graphics card (the OptiPlex in part 4.7) can make BitLocker ask for its recovery key at boot. Without the key, the drive stays locked. Do this on the OptiPlex, the-box, the-spire and Cobra1:

```powershell
# Admin PowerShell (right-click Start → Terminal (Admin))
# Shows each drive and whether BitLocker is on ("Protection On") or off
manage-bde -status
# Lists C:'s protectors. Copy the "Numerical Password" ID and its 48-digit
# password into KeePassXC, one entry per machine (repeat for D: etc. if encrypted)
manage-bde -protectors -get C:
```

- [ ] Every encrypted drive's recovery key is in KeePassXC, labelled with the machine name. A drive that shows "Protection Off" needs nothing.

### Copying Windows folders with robocopy, and checking the copy

Use this for the OptiPlex folders in the table, or any other Windows folder you want to keep. Set `$src` and `$dst` for each folder; `E:` here is the backup drive.

```powershell
# Normal PowerShell. Change these two lines for each folder you copy.
$src = "C:\LaunchBox"                       # folder to back up
$dst = "E:\backup\cobra-arcade\LaunchBox"   # where the copy goes (created if missing)
$log = "E:\backup\robocopy.log"             # one log for every run, appended to

# /E      copy subfolders, including empty ones
# /COPY:DAT /DCOPY:DAT  keep data, attributes and timestamps on files and folders
# /R:1 /W:1  retry a locked file once, after 1 s, instead of the default 1 million tries
# /XJ     skip junctions (stops endless loops through AppData links)
# /MT:16  16 copy threads
# /LOG+:  append to the log; /TEE also prints to the screen
robocopy $src $dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /MT:16 /LOG+:$log /TEE
```

**Check the copy.** Run the same copy again as a dry run. `/L` only lists, it changes nothing:

```powershell
# /L list only   /NJH no header   /NDL no folder lines   /NP no progress   /FP full paths
robocopy $src $dst /E /L /XJ /NJH /NDL /NP /FP
# In the summary table at the bottom, the "Files" row's "Copied" column must be 0.
# Anything above 0 is a file that didn't make it: run the first command again and read the log.
```

Spot-check one or two important files by hash; both lines must show the same hash:

```powershell
Get-FileHash "$src\some-file.xml", "$dst\some-file.xml" | Format-Table Hash, Path
```

### Things a folder copy won't catch

- [ ] **Browsers:** turn on browser sync, or export bookmarks and passwords. Import the passwords into KeePassXC, then delete the export file; it's plain text.
- [ ] **Old Pi-hole** (if the SGIN runs one): web UI → Settings → Teleporter → **Export**. Keep the file with the SGIN copy; its blocklists and local DNS records can be imported into Pi-hole #1 in part 2.
- [ ] **Xfinity gateway:** screenshots of the port forwards, DHCP reservations and Wi-Fi settings, next to the inventory table.
- [ ] **Windows licenses:** in an admin prompt run `slmgr /dli` on each machine to see whether it uses a product key or a linked Microsoft account, and note it.

## 0.4 songofeo.com on Porkbun

The domain stays where it is: Porkbun is the registrar **and** the DNS. The build needs plain DNS records pointing at your home IP, plus API access so OPNsense can keep the IP current (part 2.10) and the gate can get its certificate (part 5.3).

- [ ] **Nameservers:** Porkbun → Domain Management → `songofeo.com` → Details → Authoritative Nameservers are Porkbun's own (`*.porkbun.com`). If they point somewhere else (an old Cloudflare setup, say), switch them back to Porkbun's defaults and give it an hour.
- [ ] **API Access: on** for `songofeo.com` (same Details page). It's off per domain by default, and without it every API call fails.
- [ ] **Clean the DNS records** (Details → DNS Records):
  - **Keep the records Porkbun's Static Hosting created for the bare domain** (usually an **ALIAS** or **A** for `songofeo.com` and a `www` CNAME). Your public homepage lives there (the SongofEo project).
  - Delete the **`*` wildcard CNAME** if Porkbun added one (pointing at `pixie.porkbun.com` / `uixie.porkbun.com`); it would send every app name to Porkbun.
  - Delete every **AAAA** record (they're what broke things when your IP "turned into IPv6").
  - Keep any **MX/TXT** records for email you actually use.
  - If your old server is public now, create one **A** record for **`gate`** with the IPv4 from 0.2 and point its app names (CNAMEs) at `gate.songofeo.com`. OPNsense keeps `gate` up to date from part 2.10. Never put your home IP on the bare domain: that's the homepage's record.
- [ ] **URL Forwarding** (Details → URL Forwarding): remove any forwards for `songofeo.com` or names you'll use (`tv`, `docs`, …). A forward replaces the DNS answer with Porkbun's redirect servers.
- [ ] **Two API keys** (Account → API Access → Create API Key):
  - `cobra-ddns` (for OPNsense) and `cobra-acme` (for the gate)
  - If the form offers it, limit each key to the domain `songofeo.com` and to DNS permissions. Don't limit by IP; your home IP changes.
  - Each shows a **secret key once** (`sk1_…`). Store both halves in KeePassXC immediately.

## 0.5 Install media

- [ ] Proxmox VE 9 USB (done)
- [ ] **Debian 13 netinst** USB for the SGIN (Rufus, DD mode). The OPNsense and gate ISOs are downloaded straight onto Proxmox in part 1.9.
- [ ] **Windows 11** USB for the OptiPlex (Rufus with the requirement and online-account bypasses ticked; part 4.1)

## 0.6 Shopping list

| Item | Needed for | When |
|---|---|---|
| USB 3 gigabit NIC (RTL8153) | OPNsense WAN on the Latitude. A **separate** adapter from the SGIN's (the SGIN keeps its own AX88179 adapter for its LAN link; it has no built-in Ethernet) | Before part 2 |
| One more Ethernet cable | USB NIC → Xfinity | Before part 2 |
| ✅ TP-Link Omada ES210X-M2 (8× 2.5GBASE-T, 2× 10G SFP+, easy managed) | `cobra-switch`, the LAN switch, replacing the Netgear 5-port switch E (now a spare); also carries part 9's VLANs | Have it; set up in part 2.12 |
| ✅ TP-Link RE700X (AX3000 range extender, gigabit port) | The trusted `cobra` Wi-Fi AP in **Access Point mode**, cabled to cobra-switch port 6 (part 2.10b). No injector needed | Have it; part 2.10b |
| ✅ Seagate Expansion Desktop 24 TB | The rescue drive: whole-disk image of wd1 before anything touches it, then the recovered files (part 3.4r) | Have it; part 3.4r |
| ~~18–20 TB 3.5" NAS drive~~ | Not needed: the Seagate 24 TB becomes the `vault` backup drive (parts 3.4 and 5.6) once the recovered files have been fine on their drives for a few weeks | — |
| Second dual-bay dock | Two more data drives (`dock2a`, `dock2b`) | Whenever |

## Done when

- [ ] KeePassXC file exists, with a copy on USB
- [ ] Inventory table filled in, at least the MACs and port forwards
- [ ] Old server and cabinet backups copied and spot-checked (robocopy dry runs show 0 files to copy)
- [ ] BitLocker recovery keys for every encrypted Windows drive stored in KeePassXC
- [ ] `songofeo.com` on Porkbun's nameservers with API Access on; no AAAA, parking or URL-forwarding records; both API keys stored

Next: **[1. Set up Latitude](01-latitude.md)**
