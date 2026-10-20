# Debian 13 desktops: which one, or none

Reference for future cobra-server builds, October 2026. These are the choices on the Debian 13 (trixie) installer's **Software selection** screen: GNOME, KDE Plasma, Cinnamon, LXDE, LXQt, MATE and Xfce, plus the option of installing no desktop at all.

**sgin's choice:** no desktop. Stage 03 installs only *SSH server* and *standard system utilities*, sgin is managed through Cockpit and SSH, and a basic VGA monitor is attached only for servicing.

RAM figures are rough idle numbers after login on Debian 13, from the projects' docs and community reports, not measurements on our hardware.

---

## Chart

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

## How to choose

- **Headless server you manage over the network** (sgin, the gate VM, the Optiplex): no desktop. Every desktop takes RAM from the services, adds idle-suspend you have to undo, and installs NetworkManager next to the static IP. A desktop compositor also shares the Intel GPU with Quick Sync transcodes. The effect is small, but it's still extra load on the GPU.
- **Server that should have a GUI to fall back on:** install headless, then add Xfce so it starts only when you ask for it (below).
- **Machine someone actually sits at** (a workstation, a kiosk, a TV box): KDE Plasma or GNOME for a full modern desktop. KDE is lighter and easier to bend to a setup like this one; GNOME is the more familiar choice. On older or low-RAM hardware, use Xfce, or LXQt if Xfce is still too heavy.
- **Skip** LXDE (abandoned) and Cinnamon (Mint is the better home for it).

### Desktops on a laptop that runs as a server

If a laptop runs a desktop anyway, lid handling isn't enough (manual parts 1.8 and 3.3a). Also turn off the desktop's own idle suspend:

- GNOME: Settings → Power → *Automatic Suspend* off, and for the login screen: `sudo -u Debian-gdm dbus-run-session gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'`
- KDE: System Settings → Power Management → *Suspend session* → Do nothing (on AC).
- Belt and braces on any of them: `sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target`

---

## Adding a GUI to a headless install later

Install Xfce without the login screen or NetworkManager, so nothing changes until you start it by hand:

```
sudo apt install --no-install-recommends xfce4 xfce4-terminal xserver-xorg xinit
```

Log in at the console, run `startxfce4` when you need it, and log out when you're done. Afterwards, check that the machine still answers on its static IP. This is a suggested setup and hasn't been tested on our hardware yet.

To get a full desktop with a login screen later instead, use the installer's task packages: `sudo apt install task-xfce-desktop` (or `task-kde-desktop`, `task-gnome-desktop`, and so on). Expect NetworkManager to come with it.
