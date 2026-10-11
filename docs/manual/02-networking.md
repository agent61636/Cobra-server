# 2. Redo networking (OPNsense VM 100, Pi-hole CT 101)

Needs: part 1 done, Cloudflare zone active, API token (Zone.DNS Edit + Zone.Zone Read, zone `elysidrome.com`). Wired internet is down from "Flip host network" until "Recable".

## OPNsense VM (command-center, root)

```bash
qm create 100 --name open-the-box --ostype other --cpu host --cores 2 --memory 4096 --balloon 0 \
  --scsihw virtio-scsi-single --scsi0 local-lvm:32,discard=on,iothread=1 \
  --net0 virtio,bridge=vmbr1 --net1 virtio,bridge=vmbr0 \
  --cdrom local:iso/$(ls /var/lib/vz/template/iso | grep -m1 OPNsense) \
  --boot 'order=scsi0;ide2' --onboot 1 --startup order=1,up=60
qm start 100
```

- [ ] Console (UI → 100 → Console): log in `installer` / `opnsense` → Install (UFS) → disk `da0` → set root password → reboot
- [ ] `qm set 100 --delete ide2`
- [ ] Console option 1 Assign interfaces: WAN `vtnet0`, LAN `vtnet1`, no VLANs
- [ ] Option 2 Set LAN IP: `10.10.10.1/24`, no LAN DHCP yet, HTTPS GUI yes. WAN: DHCP.

## Flip host network (command-center)

```bash
sed -i 's/^iface vmbr1 inet dhcp.*/iface vmbr1 inet manual/; s/^#\s*gateway 10.10.10.1.*/        gateway 10.10.10.1/' /etc/network/interfaces
printf 'search home.arpa\nnameserver 10.10.10.1\n' > /etc/resolv.conf
ifreload -a && ip -br a
```

- [ ] Onboard port → switch. USB NIC → Xfinity. Switch's old Xfinity uplink: unplug.
- [ ] Desktop on the switch with static `10.10.10.50/24`, gw `10.10.10.1` until DHCP is on
- [ ] Xfinity app: reserve `10.0.0.2` for VM 100 WAN MAC (`qm config 100 | grep net0`), DMZ host → `10.0.0.2`. Renew WAN in OPNsense (Interfaces → Overview → WAN → Reload).

## OPNsense UI (`https://10.10.10.1`)

- [ ] Wizard: hostname `open-the-box`, domain `home.arpa`, DNS blank, untick "override DNS"; WAN DHCP; **untick "Block private networks"** on WAN (*Xfinity side is 10.0.0.0/24*)
- [ ] System → Access → Users → root: TOTP (System → Access → Servers → add TOTP, then Settings → Administration → Authentication = TOTP)
- [ ] System → Settings → Administration: listen on LAN only, HTTP redirect off, SSH off
- [ ] Services → ISC DHCPv4 (or Dnsmasq DHCP) → LAN: range `10.10.10.100–199`, DNS `10.10.10.3`, `10.10.10.1` (*change second to `10.10.10.20` after part 3*), domain `home.arpa`
- [ ] Static mappings: `.20` stream, `.30` arcade, `.40` iDRAC, `.41` R620, `.50` / `.51` desktops
- [ ] Services → Unbound DNS → General: enable, listen LAN + WireGuard. DNS over TLS: `1.1.1.1:853` host `cloudflare-dns.com`, `9.9.9.9:853` host `dns.quad9.net`
- [ ] System → Firmware → Plugins: `os-ddclient`, `os-crowdsec`
- [ ] Services → Dynamic DNS: backend native, Cloudflare, username = zone `elysidrome.com`, password = token, hostname `elysidrome.com`, check IP via interface WAN **no**, via web service (`cloudflare-ipv4`) — *WAN IP is 10.0.0.2, not public*
- [ ] Cloudflare: CNAMEs to `elysidrome.com` for app hostnames are added in part 5. All **DNS only (grey)**.
- [ ] VPN → WireGuard → Instances: `wg0`, port `51820`, tunnel `10.10.99.1/24`, generate keys. Peers: one per device, allowed IPs `10.10.99.N/32`. Enable.
- [ ] Interfaces → Assignments: add `wg0` as `WG`, enable
- [ ] Firewall → Rules → WAN: pass UDP `51820` to WAN address. WG: pass any to LAN net.
- [ ] Services → Intrusion Detection → Administration: enable, IPS mode, interface WAN, pattern Hyperscan; Download: ET open, enable all, download & update. (*IPS mode needs Interfaces → Settings: disable hardware CRC/TSO/LRO, reboot*)
- [ ] Services → CrowdSec: enable LAPI, agent, bouncer

Client config (phone/laptop WireGuard app):

```ini
[Interface]
PrivateKey = <client private>
Address = 10.10.99.2/32
DNS = 10.10.10.3
[Peer]
PublicKey = <wg0 public>
Endpoint = elysidrome.com:51820
AllowedIPs = 10.10.10.0/24, 10.10.99.0/24
PersistentKeepalive = 25
```

## Pi-hole CT 101 (command-center)

```bash
TPL=$(ls /var/lib/vz/template/cache | grep -m1 debian-13-standard)
pct create 101 local:vztmpl/$TPL --hostname pihole-1 --cores 1 --memory 512 --rootfs local-lvm:4 \
  --net0 name=eth0,bridge=vmbr0,ip=10.10.10.3/24,gw=10.10.10.1 --nameserver 10.10.10.1 \
  --unprivileged 1 --features nesting=1 --onboot 1 --startup order=2
pct start 101 && pct enter 101
```

Inside CT 101:

```bash
apt update && apt full-upgrade -y && apt install -y curl
curl -sSL https://install.pi-hole.net | bash          # upstream: custom 10.10.10.1
pihole setpassword
pihole-FTL --config dns.upstreams '["10.10.10.1"]'
pihole-FTL --config misc.dnsmasq_lines '["address=/elysidrome.com/10.10.10.10"]'
pihole-FTL --config dns.hosts '["10.10.10.1 open-the-box.home.arpa","10.10.10.2 command-center.home.arpa","10.10.10.3 pihole-1.home.arpa","10.10.10.10 elysidrome-gate.home.arpa","10.10.10.20 elysidrome-stream.home.arpa","10.10.10.30 elysidrome-arcade.home.arpa"]'
exit
```

## Recable + check

- [ ] Desktops back to DHCP (they get `.50`/`.51`)
- [ ] `nslookup tv.elysidrome.com` → `10.10.10.10`; `nslookup google.com` works; `http://10.10.10.3/admin` shows queries
- [ ] Proxmox UI now at `https://10.10.10.2:8006`
- [ ] WireGuard from phone on cellular reaches `https://10.10.10.2:8006`
