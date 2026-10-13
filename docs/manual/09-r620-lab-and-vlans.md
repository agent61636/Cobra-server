# 9. R620 security lab and VLANs

**Result:** the R620 is a second Proxmox server you power on from your desk for lab sessions and off afterwards. Lab machines (Active Directory, Wazuh, Security Onion, CAPEv2 malware sandbox, IncusOS) live on their own networks, so nothing in the lab can reach the family's machines.

**Needs:** parts 1–5. Phase B needs a **managed switch** (802.1Q VLANs), such as an 8- or 16-port "smart" switch. A plain unmanaged switch passes tagged traffic but can't separate it.

## The decisions, and why

| Decision | Why |
|---|---|
| **The R620 is its own Proxmox server, not clustered with `cobra-command`** | A two-node Proxmox cluster needs both nodes for a majority. With the R620 off most of the time, `cobra-command` would lose quorum and go read-only, which means it couldn't start or change VMs, *including the firewall*. Two standalone servers avoid that. To see both in one place, use **Proxmox Datacenter Manager** (stable 1.0 since Dec 2025), or just keep two browser tabs. |
| **Power on and off remotely** | The R620 draws 110–160 W. Its iDRAC (the built-in management controller) can power it on over the network. |
| **Lab traffic on its own VLANs, phase B** | Malware samples and attack tools must never share a network with the desktops, the cabinet or the NAS. VLANs make one switch act like several separate ones, and OPNsense decides what may cross. |
| **CAPEv2's detonation network has no internet at all** | A sandboxed sample that can reach the internet can spread, phone home, or get your IP blocklisted. |
| **The PERC RAID controller builds one RAID 10 from the 4 SSDs; Proxmox uses LVM-thin on top** | The R620's PERC does hardware RAID well, and that's the supported path. ZFS wants the disks passed through raw, which the PERC H710 can't do. (If yours is a PERC H310, it can: set the disks to non-RAID and pick ZFS RAID 10 in the installer instead.) |

## Phase A: the R620 on the main LAN (no new switch)

### 9.1 iDRAC first

- [ ] Cable the iDRAC port → switch. At boot press **F2 → iDRAC Settings → Network**: static IP `10.6.9.40/24`, gateway `10.6.9.1`. **User Configuration**: change the default `root` / `calvin` password to a generated one.
- [ ] Browser: `https://10.6.9.40` → log in → update the iDRAC firmware and BIOS (Maintenance → System Update) before installing anything
- [ ] Settings → Network → **IPMI over LAN: Enabled** (used for power-on below)
- iDRAC is **never** port-forwarded. Reach it from the LAN or over WireGuard only.

### 9.2 Disks and install

- [ ] At boot, **Ctrl+R** (PERC setup): create one virtual disk, **RAID 10** over the 4 SSDs, default stripe. Initialize.
- [ ] Install Proxmox VE 9 exactly like part 1.4, with these differences: hostname **`cobra-lab.home.arpa`**, IP **`10.6.9.41/24`**, gateway and DNS `10.6.9.1`, target disk = the PERC virtual disk.
- [ ] Then parts 1.6 (no-subscription repo, updates) and 1.7 (eels admin, 2FA, SSH keys) on this server too. Skip 1.8 (laptop settings).
- [ ] Add it to the Pi-holes' local names: in `dns.hosts` on both (parts 2.9 and 3.9), add `"10.6.9.41 cobra-lab.home.arpa cobra-lab"` and `"10.6.9.40 cobra-lab-idrac.home.arpa cobra-lab-idrac"`.

### 9.3 Power on and off from cobra-command

On cobra-command (root):

```bash
apt install -y ipmitool
install -m 600 /dev/null /root/.idrac && echo '<iDRAC root password>' > /root/.idrac
cat > /usr/local/bin/lab <<'EOF'
#!/bin/sh
# lab on | off | status
I="ipmitool -I lanplus -H 10.6.9.40 -U root -f /root/.idrac"
case "$1" in
  on)     $I chassis power on ;;
  off)    ssh root@10.6.9.41 poweroff ;;          # clean shutdown; VMs stop first
  status) $I chassis power status ;;
  *)      echo "usage: lab on|off|status"; exit 1 ;;
esac
EOF
chmod 755 /usr/local/bin/lab
lab status
```

- [ ] `lab on`; about 3 minutes later `https://10.6.9.41:8006` answers. `lab off` shuts it down cleanly.
- [ ] For `lab off` to work without a password: `ssh-copy-id root@10.6.9.41` from cobra-command once.
- [ ] Proxmox on cobra-lab → Datacenter → Options → keep **"Start on boot"** off for lab VMs, so a power-on doesn't start malware tools by itself.

### 9.4 Backups

- [ ] cobra-lab → Datacenter → Storage → Add → **Proxmox Backup Server**: the same `pbs-stream` details as part 5.6 (server `10.6.9.20`, datastore `store1`, user `pve@pbs`, the fingerprint). Back up only the lab VMs worth keeping (the AD domain controller, Wazuh). **Never** back up the CAPE sandbox guests or anything that has held live malware.

Phase A is fine for the Active Directory lab and Wazuh. **Don't run CAPEv2 or live malware until phase B** gives the lab its own network.

## Phase B: VLANs (managed switch)

### Network plan

| VLAN | Name | Subnet | Who's on it | May reach |
|---|---|---|---|---|
| untagged (1) | LAN | `10.6.9.0/24` | Everything you have today | Everything (as now) |
| 20 | LAB | `10.6.20.0/24` | AD lab, Wazuh, Security Onion, IncusOS, attacker VMs | Internet; other LAB machines. **Not** the LAN. |
| 21 | DETONATE | `10.6.21.0/24` | CAPEv2 analysis guests only | **Nothing**: no internet, no LAN, only the CAPE host's result collector |
| 30 | MGMT | `10.6.30.0/24` | The R620's iDRAC (moves from `10.6.9.40` to `10.6.30.40`) | Nothing; only LAN/VPN admins may reach *it* |

The LAN keeps its numbers, so nothing from parts 1–8 changes.

### 9.5 The switch

Set the switch's own management IP on the LAN (e.g. `10.6.9.5`), change its admin password, then set up its ports (names vary by brand: "802.1Q VLAN", "tagged/untagged", "PVID"):

| Port goes to | Untagged | Tagged | PVID |
|---|---|---|---|
| Latitude onboard NIC (OPNsense LAN) | 1 | 20, 21, 30 | 1 |
| R620 NIC 1 (Proxmox) | 1 | 20, 21 | 1 |
| R620 iDRAC | 30 | — | 30 |
| Everything else (desktops, SGIN, OptiPlex, Wi-Fi AP) | 1 | — | 1 |

### 9.6 Pass VLANs through to OPNsense (cobra-command)

The Latitude's bridge must carry the tags into the OPNsense VM. Edit `/etc/network/interfaces`, under `iface vmbr0 inet static`, adding two lines:

```
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

```bash
ifreload -a && bridge vlan show dev enp0s31f6 | head     # VLANs 2-4094 listed on the NIC
```

The host's own address stays untagged at `10.6.9.2`, and OPNsense's LAN NIC (`net1`, no `tag=`) now receives every VLAN.

### 9.7 OPNsense interfaces and rules

For each of LAB (20), DETONATE (21) and MGMT (30):

- [ ] **Interfaces → Devices → VLAN** (older versions: Interfaces → Other Types → VLAN) → Add: parent `vtnet1` (LAN), tag, description. Save.
- [ ] **Interfaces → Assignments**: add the new VLAN device, then open it: Enable, description (`LAB`, `DETONATE`, `MGMT`), IPv4 **Static**, `10.6.20.1/24` (`.21.1`, `.30.1`). Save, Apply.
- [ ] DHCP for LAB only (same DHCP page as part 2.6): range `10.6.20.100–199`, DNS `10.6.20.1` (OPNsense's Unbound; add LAB to Unbound's listen interfaces). DETONATE gets no DHCP from OPNsense; CAPE manages its guests' addresses. MGMT is static only.

Firewall (**Firewall → Aliases**: create `PRIVATE` = `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16`):

| Interface | Rules, top to bottom |
|---|---|
| **LAB** | Pass LAB net → LAB address port 53 (DNS) · **Block** LAB net → `PRIVATE` · Pass LAB net → any (internet) |
| **DETONATE** | **Block** everything (the default with no pass rules). CAPE's result channel runs inside the R620 itself, not through OPNsense. |
| **MGMT** | **Block** everything leaving MGMT |
| **LAN** (add above the default allow) | Pass LAN net → MGMT net ports 443, 5900 (iDRAC web and console), 623/udp (IPMI) · Pass LAN net → LAB net (you can reach the lab; it can't reach you, because replies are allowed but new connections from LAB are blocked above) |
| **WG** | Same two passes as LAN, so you can run the lab from outside over WireGuard |

- [ ] Move the iDRAC: in its settings, IP `10.6.30.40/24`, gateway `10.6.30.1`, then move its cable to the MGMT switch port. Update the `lab` script to `-H 10.6.30.40`, and the Pi-hole name.

### 9.8 The R620's bridges (cobra-lab)

Same edit as 9.6 on the R620's `vmbr0` (`bridge-vlan-aware yes`, `bridge-vids 2-4094`). Then a lab VM goes on a VLAN by setting its NIC's **VLAN tag** (VM → Hardware → Network Device → VLAN Tag `20` or `21`). A VM with no tag is on the family LAN, so tag every lab VM.

- [ ] A test VM with tag `20` gets `10.6.20.1xx`, reaches the internet, and **can't** ping `10.6.9.20`
- [ ] The same VM with tag `21` can't reach anything
- [ ] From a desktop: you can SSH into the tag-20 VM

## 9.9 What to build in the lab

| Lab | Network | Notes |
|---|---|---|
| **Active Directory** | LAB | Windows Server evaluation VMs (180-day trial, free from Microsoft's Evaluation Center): one domain controller, one or two Windows 11 Enterprise eval clients. Use your own domain name that isn't public, e.g. `lab.cobra.internal`. |
| **Wazuh** (SIEM/XDR) | LAB | The all-in-one OVA or a Debian VM with Wazuh's install script; agents on the AD machines. Give it 8 GB RAM and 4 cores. |
| **Security Onion** | LAB | Network security monitoring. It's hungry: 16 GB+ RAM and 200 GB+ disk for a standalone eval install. Mirror the LAB VLAN to it with a Linux bridge port in promiscuous mode, or start with its import mode on capture files. |
| **CAPEv2** | host on LAB, guests on **DETONATE** | The CAPE host VM gets two NICs: one tagged 20 (for you to reach its web UI), one tagged 21 (for its analysis guests). Guests are Windows VMs without internet. Snapshot them clean, never back them up, and never move files from DETONATE to anywhere else except CAPE's reports. |
| **IncusOS** | LAB | A learning VM: the immutable OS that only runs Incus containers and VMs (overview §1). |

R620 RAM is the limit. Check yours (iDRAC → System → Memory). Running AD + Wazuh + Security Onion together needs about 40 GB.

## Done when

- [ ] `lab on` / `lab off` from cobra-command
- [ ] iDRAC reachable only from LAN/VPN (and, after phase B, only on MGMT)
- [ ] A LAB VM can't reach the family LAN; a DETONATE VM can't reach anything
- [ ] `cobra-command` stays fully usable while the R620 is off (it isn't in a cluster)

## Sources

- Proxmox Cluster Manager (quorum, QDevice for two-node clusters): https://pve.proxmox.com/wiki/Cluster_Manager
- Proxmox Datacenter Manager 1.0 announcement: https://forum.proxmox.com/posts/821973/
- OPNsense VLAN walkthrough (older menu names): https://homenetworkguy.com/how-to/configure-vlans-opnsense/
