# Linux builds for future machines

Reference for future cobra-server builds, October 2026. Two charts:

1. **Debian 13 desktops:** the choices on the Debian 13 (trixie) installer's **Software selection** screen (GNOME, KDE Plasma, Cinnamon, LXDE, LXQt, MATE and Xfce), plus installing no desktop at all.
2. **Purpose-built distros:** security, media, gaming and storage builds such as Kali, Bazzite and Batocera, for a machine that does one job.

**sgin uses no desktop.** Stage 03 installs only *SSH server* and *standard system utilities*, sgin is managed through Cockpit and SSH, and a basic VGA monitor is attached only for servicing.

Figures and version numbers are as of October 2026. RAM figures are rough idle numbers after login on Debian 13, from the projects' docs and community reports, not measurements on our hardware.

---

## 1. Debian 13 desktops

| Choice | Idle RAM | Pros | Cons for a server |
|---|---|---|---|
| **No desktop** (standard system utilities only) | ~200 MB | Smallest footprint and fewest updates. No login screen that can suspend the machine. The installer keeps Debian's plain `/etc/network/interfaces` setup for a static IP. Cockpit gives a web GUI for logs, services, storage, updates and a terminal. | The local screen shows only a text console. Fixing a broken network means typing at that console. |
| **GNOME** (48) | 1.2–1.5 GB | Polished and familiar. Wayland by default. Built-in remote desktop (RDP) server. | Heaviest choice. Its login screen (GDM) auto-suspends after about 15 minutes idle, even on AC power, unless you turn that off. Pulls in NetworkManager, which can clash with a static IP set the Debian way. Lots of packages to update. |
| **KDE Plasma** (6.3) | 0.9–1.2 GB | Very configurable and modern. Wayland by default. Built-in RDP server (KRDP). Good file manager (Dolphin). | Still heavy. Its power manager also suspends on idle unless you change it. Pulls in NetworkManager. Many settings to learn for a screen that's rarely used. |
| **Cinnamon** (6.4) | 700–900 MB | Windows-like layout, easy to pick up. | Built mainly for Linux Mint, so Debian's copy is less polished. X11 in practice (Wayland is experimental). Mid-weight with no clear win over Xfce. |
| **LXDE** | 300–400 MB | Very light. | Effectively abandoned; its developers moved to LXQt. Old GTK2 toolkit. Don't start a new build on it. |
| **LXQt** (2.1) | 400–500 MB | Light and maintained. Qt-based, so it feels a little like KDE. | Fewer built-in tools. Wayland support is still partial. Smaller community for Debian-specific help. |
| **MATE** (1.26) | 500–600 MB | The classic GNOME 2 layout. Very stable. | Slow development, X11 only. Works fine but feels dated. |
| **Xfce** (4.20) | 500–700 MB | Light and rock solid; the usual pick for a server that needs a GUI. Works well over xrdp. Easy to keep from starting at boot. | Plain look. X11 by default (Wayland is experimental). The full installer task still adds NetworkManager and a login screen. |

---

### Choosing a desktop

- **Headless server you manage over the network** (sgin, the gate VM, the Optiplex): no desktop. Every desktop takes RAM from the services, adds idle-suspend you have to undo, and installs NetworkManager next to the static IP. A desktop compositor also shares the Intel GPU with Quick Sync transcodes. The effect is small, but it's still extra load on the GPU.
- **Server that should have a GUI to fall back on:** install headless, then add Xfce so it starts only when you ask for it (below).
- **Machine someone actually sits at** (a workstation, a kiosk, a TV box): KDE Plasma or GNOME for a full modern desktop. KDE is lighter and easier to bend to a setup like this one; GNOME is the more familiar choice. On older or low-RAM hardware, use Xfce, or LXQt if Xfce is still too heavy.
- **Skip** LXDE (abandoned) and Cinnamon (Mint is the better home for it).

#### Desktops on a laptop that runs as a server

If a laptop runs a desktop anyway, lid handling isn't enough (manual parts 1.8 and 3.3a). Also turn off the desktop's own idle suspend:

- GNOME: Settings → Power → *Automatic Suspend* off, and for the login screen: `sudo -u Debian-gdm dbus-run-session gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'`
- KDE: System Settings → Power Management → *Suspend session* → Do nothing (on AC).
- Belt and braces on any of them: `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`

---

### Adding a GUI to a headless install later

Install Xfce without the login screen or NetworkManager, so nothing changes until you start it by hand:

```
sudo apt install --no-install-recommends xfce4 xfce4-terminal xserver-xorg xinit
```

Log in at the console, run `startxfce4` when you need it, and log out when you're done. Afterwards, check that the machine still answers on its static IP. This is a suggested setup and hasn't been tested on our hardware yet.

To get a full desktop with a login screen later instead, use the installer's task packages: `sudo apt install task-xfce-desktop` (or `task-kde-desktop`, `task-gnome-desktop`, and so on). Expect NetworkManager to come with it.

---

## 2. Purpose-built distros

These replace Debian entirely on a machine that does one job. Most are image-based or appliance-style: you don't manage them package by package the way the manual manages Debian, and several don't run Podman or Cockpit at all. Pick one when the box's whole purpose matches the distro's; otherwise stick with Debian and run the tool as a container or app.

**A note on Calamares:** Calamares isn't a distro. It's a graphical installer framework that many distros use instead of their own installer, among them the Debian *live* images, Lubuntu, Manjaro and EndeavourOS. On Debian, the live ISO's "Install Debian" icon is Calamares, while the netinst ISO the manual uses runs the classic text installer, which has the Software selection screen that chart 1 is about. Calamares is quicker and friendlier but offers fewer choices, so the netinst installer is still the better fit for a server.

### Security

| Build | Based on | Good for | Watch out for |
|---|---|---|---|
| **Kali Linux** | Debian testing (rolling) | Penetration testing and CTFs. Hundreds of security tools come preinstalled. Runs from USB, in a VM, or on a Pi. A good fit for the R620 lab VLAN. | An attack toolkit, not a daily or server OS. Rolling updates occasionally break things. Keep it on the lab VLAN, never on the trusted LAN or facing the internet. |
| **Parrot Security** | Debian stable | The same job as Kali with a lighter footprint, plus a privacy-focused Home edition. | Smaller community than Kali. Same rule: lab VLAN only. |
| **Security Onion** | Its own ISO on an enterprise Linux base | Network security monitoring for the whole house: IDS (Suricata), network logs (Zeek), packet capture and a dashboard. Watch what crosses OPNsense. | Heavy: plan on 16 GB of RAM or more, several cores, lots of disk, and a second NIC on a mirror/SPAN port. Not for the SGIN or the Optiplex. The R620 is the only box here that could run it, and it's not on 24/7. |
| **Tails** | Debian, live USB only | Private browsing on any PC: everything goes through Tor and nothing is saved by default. | Not installable as a server. Slow, by design. |
| **Qubes OS** | Xen hypervisor | A security-focused workstation: each task runs in its own isolated VM. | Needs a strong machine with VT-x/VT-d and 16 GB+ RAM. A big learning curve. No use as a server. |
| **OPNsense / pfSense** | FreeBSD | Firewall and router, already in use as the Cobra gateway (part 1). | Listed here only for completeness; not Linux. |

### Media and retro gaming

| Build | Based on | Good for | Watch out for |
|---|---|---|---|
| **Batocera** | Buildroot (its own appliance image) | Plug-in-and-play retro console: boot from USB or SD, pick a game with a controller. Runs on PCs, Pis and handhelds. Can read ROMs over the network, so it could use the `\\cobra-stream\roms` share. | An appliance: no package manager, no server duties, settings live in its own config files. |
| **Recalbox / RetroPie / Lakka** | Buildroot / Raspberry Pi OS / LibreELEC | The same idea as Batocera. RetroPie is the Pi classic, Lakka is RetroArch with nothing else, Recalbox is the simplest. | Batocera supports the most hardware and emulators of the group; pick one of these only for a specific reason. |
| **Bazzite** | Fedora Atomic (Universal Blue) | A living-room gaming PC or handheld: Steam in game mode like a Steam Deck, Nvidia and AMD drivers included, HDR, and image-based updates you can roll back. Desktop editions come with KDE or GNOME. | Image-based, so system changes go through containers (Distrobox) or rpm-ostree layering rather than plain installs. Fedora, not Debian, so commands in this manual don't carry over one for one. |
| **ChimeraOS / SteamOS** | Arch | A pure Steam console that boots straight to Big Picture. | Very little beyond Steam. SteamOS's official support for non-Valve hardware is still limited; check the current hardware list first. |
| **LibreELEC / CoreELEC / OSMC** | Their own minimal images | A TV box that only runs Kodi. Kodi can play from Jellyfin with the Jellyfin for Kodi add-on, so it works well as a client on an old mini PC or a Pi. | Clients only, not servers. CoreELEC is for Amlogic TV boxes, OSMC mainly for Pis and Vero devices. |
| **Ubuntu Studio / AV Linux** | Ubuntu / Debian | Audio and video production: low-latency kernel, DAWs, video editors, OBS. A workstation for making content for the radio station or the site. | A creative workstation, not a server. |

### Storage and home servers

| Build | Based on | Good for | Watch out for |
|---|---|---|---|
| **OpenMediaVault** | Debian | A NAS with a web GUI for shares, RAID or mergerfs/SnapRAID, and Docker/Compose. The closest thing to what sgin does by hand, behind a GUI. | Wants to own the whole machine's config: don't mix it with hand-edited Samba or fstab like the manual's. |
| **TrueNAS Community Edition** (formerly SCALE) | Debian | ZFS storage with snapshots and replication, plus apps. Strong for a box that holds important data. | ZFS wants matched drives and plenty of RAM (8 GB minimum, more is better). Not for a USB drive hub. The base system is locked down; you don't apt install on it. |
| **Unraid** | Slackware | Mixed-size drives with parity, plus Docker and VMs, all from a web GUI. | Paid licence. Boots from a USB stick. |
| **Proxmox VE** | Debian | A hypervisor for VMs and LXC containers; the Latitude already runs it as the gateway host (part 1). | Not a desktop. Wants a machine with VT-x and enough RAM to split between guests. |
| **Home Assistant OS** | Buildroot | Home automation and smart-home dashboards, cameras and sensors. Runs as an appliance or as a VM on Proxmox. | Appliance: one job only. A VM on Proxmox is usually easier than giving it a whole machine. |

### Choosing a purpose-built distro

- **Server that runs many services:** Debian (chart 1, no desktop), like sgin. Run single tools as Podman containers instead of reaching for an appliance OS.
- **Security lab:** Kali or Parrot on the R620 lab, on the lab VLAN (part 9). Security Onion only if a machine with the RAM and a mirror port can stay on.
- **Living-room retro console:** Batocera on a spare mini PC or Pi, pointed at the ROM share.
- **Living-room PC gaming:** Bazzite.
- **TV client for Jellyfin:** LibreELEC with the Jellyfin add-on, or just the Jellyfin app on the TV.
- **Storage-first box:** TrueNAS for ZFS on matched drives, OpenMediaVault for a Debian NAS with a GUI.
