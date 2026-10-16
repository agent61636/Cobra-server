# cobra-server

Build manual for the Cobra home network (public domain: `songofeo.com`): a Proxmox/OPNsense gateway on a Latitude, a Debian media and storage box on the SGIN, a Windows 11 arcade cabinet on the OptiPlex, and a public gate VM.

Start with the overview, then follow the parts in order.

| Part | File |
|---|---|
| Overview | [docs/manual/00-overview-architecture.md](docs/manual/00-overview-architecture.md) |
| 0. Before you start | [docs/manual/00-prep.md](docs/manual/00-prep.md) |
| 1. Latitude (Proxmox) | [docs/manual/01-latitude.md](docs/manual/01-latitude.md) |
| 2. Networking (OPNsense, Pi-hole #1) | [docs/manual/02-networking.md](docs/manual/02-networking.md) |
| 3. SGIN (media, Samba, Pi-hole #2, PBS) | [docs/manual/03-sgin.md](docs/manual/03-sgin.md) |
| 4. OptiPlex (arcade) | [docs/manual/04-optiplex.md](docs/manual/04-optiplex.md) |
| 5. Gate VM, go public, backups | [docs/manual/05-final-touches.md](docs/manual/05-final-touches.md) |
| 6. Breaks between episodes (cobra-breaks) | [docs/manual/06-tv-breaks-plugin.md](docs/manual/06-tv-breaks-plugin.md) |
| 7. Hiscore board (scores.songofeo.com) | [docs/manual/07-hiscore-platform.md](docs/manual/07-hiscore-platform.md) |
| 8. Landing site and radio | [docs/manual/08-site-and-radio.md](docs/manual/08-site-and-radio.md) |
| 9. R620 lab and VLANs | [docs/manual/09-r620-lab-and-vlans.md](docs/manual/09-r620-lab-and-vlans.md) |

Plain `podman run` scripts for every app (an alternative to the Quadlet files in parts 3, 5, 7 and 8): [`scripts/podman`](scripts/podman/README.md).

Apps built for this setup: [`apps/hiscore`](apps/hiscore) (score server), [`apps/hiscore-agent`](apps/hiscore-agent) (cabinet uploader), [`apps/cobra-breaks`](apps/cobra-breaks) (episode breaks), [`apps/site`](apps/site) (landing page), [`apps/radio`](apps/radio) (radio script).
