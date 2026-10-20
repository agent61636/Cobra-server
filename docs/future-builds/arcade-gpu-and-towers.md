# Arcade cabinet GPU: stay in the 7040 or move to a bigger tower

Reference for a future cobra-arcade build, October 2026. The cabinet is an **OptiPlex 7040 Mini Tower** (i7-6700, 16 GB, Dell 240 W supply, see [part 4](../manual/04-optiplex.md)). The goal is modern PC fighting games such as MK11 and MK1, which are locked to 60 fps.

Two charts:

1. **GPUs for the 7040 as it is,** plus the power-supply mod.
2. **Cheap refurbished towers** that take a full-size NVIDIA card with a power cable.

Prices are rough used/refurbished US figures for October 2026 and move a lot. Performance is relative to the RTX 3050 6 GB and comes from published reviews, not tests on our hardware.

---

## Why the 7040 tops out where it does

- **Power:** the Dell 240 W supply has **no PCIe power cables**, so the card must run on the slot's 75 W. That rules out every RTX 3060, 4060 and 5060.
- **Supply swap is non-standard:** Dell's board uses its own small main power connector (not a 24-pin ATX), so a normal supply needs an adapter cable, and it mounts at a slight angle in the case.
- **Card size:** about 230 mm long and 140 mm tall max (figure for the near-identical 7050 MT case). ⚠️ Verify: measure the 7040 from the slot bracket to the drive cage.
- **CPU:** the i7-6700 is fine at MK1's 60 fps cap (MK1 minimum is an i5-6600, recommended an i5-8400). Beyond an RTX 3060-class card, the CPU becomes the limit.
- **Windows 11:** a 6th-gen Intel CPU isn't on Microsoft's supported list. It runs Windows 11 via Rufus's bypass (part 4), and an 8th-gen or newer tower doesn't need the bypass.

---

## 1. Options inside the OptiPlex 7040 MT

| Option | Power | Speed vs RTX 3050 6 GB | MK1 at 1080p / 60 | Rough cost | Notes |
|---|---|---|---|---|---|
| **RTX 3050 6 GB** (Zotac Solo, MSI LP, Gigabyte LP) | 70 W, slot only | 1× (baseline) | Low/medium + DLSS | $150–180 new | The plan in part 4.7. No mods. Carries over to a new tower later. |
| **RTX A2000** (6 or 12 GB, low-profile workstation card) | 70 W, slot only | ~1.2–1.3× ⚠️ Verify | Medium + DLSS | $250–350 used | Same no-mod install, a step faster. Comes with a low-profile bracket; a full-height bracket is sold separately. Uses NVIDIA's workstation driver, which runs games fine. |
| **RTX 2000 Ada** (16 GB, low-profile) | 70 W, slot only | ~1.5× ⚠️ Verify | Medium/high | $550–700 used | Newer generation with DLSS 3 frame generation. Costs nearly as much as a whole refurbished tower. |
| **RTX 4000 SFF Ada** (20 GB, low-profile) | 70 W, slot only | ~2× (about an RTX 3060 Ti) | High | $900+ used | The fastest card that runs on slot power alone. Too expensive for a cabinet. |
| **Supply mod:** SFX supply (450–600 W) + Dell adapter cable, then an **RTX 3060 12 GB** or **RTX 4060** | 115–170 W, needs PCIe cable | ~1.8–2× | High | Supply $80–120 + adapter $15 + card $200–300 | Works and is well documented on the 7040/7050, but it's a mod: an adapter on the motherboard power and a supply mounted at an angle. Don't go past a 3060/4060-class card on this CPU. |
| **Avoid:** RTX 3050 **8 GB**, GTX 1650 / 1650 Super | 75–130 W | lower, or needs a cable | | | The 8 GB 3050 needs an 8-pin cable. A GTX 1650 is slower than the 3050 6 GB and has no DLSS. |

---

## 2. Cheap refurbished towers that take a full NVIDIA card

All of these are 8th-gen Intel or newer (official Windows 11 support) with a standard-size x16 slot and, **in the right supply option**, a PCIe power cable. Check the listing for the supply wattage before buying: the low-wattage version of each has no GPU cable.

| Tower | Typical CPU | Get the supply | GPU it can run | Rough refurb price | Notes |
|---|---|---|---|---|---|
| **Dell Precision 3630 Tower** | i7-8700 (6 cores) | 460 W (avoid 300 W) | RTX 3060 / 4060 class, up to about 200 W | $200–300 | Same Dell parts and BIOS as the OptiPlex, so part 4 carries over almost unchanged. Workstation board, quiet. ⚠️ Verify the 460 W unit's GPU cable on the listing. |
| **Dell Precision 3640 / 3650 Tower** | i7-10700 / i7-11700 (8 cores) | 500 W or higher option | RTX 3060 Ti / 4060 Ti class | $300–450 | A newer CPU with more headroom for future games. ⚠️ Verify wattage options on the listing. |
| **HP Z2 G4 Tower** | i7-8700 or Xeon E-2100 | 500 W | RTX 3060 / 4060 class | $200–300 | Same idea in HP. HP's supply and cables are proprietary too, but the 500 W version includes a GPU cable. |
| **Lenovo ThinkStation P330 Tower** | i7-8700 | 400 W (avoid 250 W) | RTX 3060 / 4060 class | $200–300 | Smaller case, so check card length (dual-fan cards, not triple). |
| **Used standard ATX gaming PC** (marketplace) | i5-10400 / Ryzen 5 3600 or newer | Any decent 550 W+ ATX | Anything that fits | $300–500 with a GPU | Most flexible: standard parts, any supply and case. Condition varies; check the supply's brand and run a stress test before paying. |

---

## Recommendation

1. **Now:** put the **RTX 3050 6 GB** in the 7040 (part 4.7). It runs MK11 well and MK1 at 60 with DLSS, and it's the cheapest way to see whether the cabinet's games need more.
2. **If MK1 or newer games feel short:** skip the supply mod and buy a **Precision 3630 or 3640 tower with the bigger supply**. Move the 3050 over first, then add an RTX 3060 / 4060-class card when one comes up cheap. The 7040 can then become a spare or a second Windows box.
3. **Only consider the slot-powered workstation cards** (A2000 and up) if one turns up far below the prices above. At typical prices, a tower plus a gaming card gets you more for the same money.

## Sources

- OptiPlex 7040 MT: 240 W supply and slot layout, [hardware-corner.net](https://www.hardware-corner.net/compare/Dell-OptiPlex-7040-MT_vs_Dell-OptiPlex-7040-SFF/)
- OptiPlex 7050 MT/SFF upgrade guide: card size limit, SFX supply mod, GPU picks, notes on the 7040, [hardware-corner.net](https://www.hardware-corner.net/guides/optiplex-7050-gaming-upgrade/)
- RTX 4000 SFF Ada benchmarked near an RTX 3060 Ti at 70 W, [Tom's Hardware](https://tomshardware.com/news/rtx-4000-sff-benchmarked)
- Precision 3630 supply sizing discussion, [Dell Community](https://www.dell.com/community/en/conversations/precision-fixed-workstations/upgrade-graphich-card-rtx-for-precision-workstation-3630/647f98b5f4ccf8a8debde78a)
- MK1 PC requirements, [Club386](https://www.club386.com/mortal-kombat-1-pc-system-specs-demand-directx-12-support/)
