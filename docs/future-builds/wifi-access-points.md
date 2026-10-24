# Wi-Fi access points

The access point you plug into the LAN switch (cobra-switch, the TP-Link Omada ES210X-M2, port 6) gives your own devices Wi-Fi **inside** OPNsense, on `10.6.9.x`. Setup steps are in the manual, **[part 2.10b](../manual/02-networking.md)**. This page compares the models that were considered for it.

**What matters for this build**

- **Standalone management:** the access point is set up from its own web page, with no cloud account and no controller app running somewhere else.
- **One SSID per VLAN:** part 9 adds VLANs. A guest/IoT Wi-Fi network on its own VLAN is what lets you retire the Xfinity Wi-Fi later.
- **PoE+ power:** these access points don't come with a power adapter, and the switch doesn't supply power (see below).

## Comparison

Prices were checked in October 2026 and are approximate.

| Model | Wi-Fi | Bands | Wired port | Power draw | Standalone management | Price | Verdict |
|---|---|---|---|---|---|---|---|
| **TP-Link Omada EAP772** | 7 | 2.4 / 5 / **6 GHz** | 2.5 GbE | PoE+ (802.3at), 25.4 W max | **Yes**, full web UI | ~$160–170 | **Top pick.** 6 GHz is a clean band for new laptops and phones, and VLAN per SSID is ready for part 9. |
| TP-Link Omada EAP723 | 7 | 2.4 / 5 GHz | 2.5 GbE | PoE+ (802.3at) | **Yes**, full web UI | ~$85–90 | **Budget pick.** Same UI and VLAN support with no 6 GHz. Plenty for 4K streams. |
| Zyxel NWA110BE | 7 | 2.4 / 5 / 6 GHz | 2.5 GbE | PoE+ (21.5 W), **or USB-C** | **Yes**, full web UI and CLI | ~$140 | **Good alternative.** It can run from a USB-C charger instead of an injector. |
| Grandstream GWN7672 | 7 | 2.4 / 5 / 6 GHz | 2.5 GbE | PoE+ (25 W) | Yes, with a controller built into the AP | ~$155–165 | Solid, but its menus are less friendly than Omada's for a single AP. |
| Ubiquiti UniFi U7 Pro XG / U7 Pro | 7 | 2.4 / 5 / 6 GHz | 2.5 GbE (XG: 10 GbE) | PoE+ (22 W) | **Limited** (phone app only) | ~$190–260 | **Skip.** The full feature set needs a UniFi controller running somewhere, which is one more service to keep alive. |
| Old router or mesh kit in "AP mode" | varies | varies | usually 1 GbE | its own adapter | varies | $0 (reuse) | **Stopgap only.** Most can't put an SSID on a VLAN, so it can't grow into part 9. |

## Power: PoE+ injector

cobra-switch (the ES210X-M2) has 2.5 GbE ports but **no PoE**, so it can't power an access point. Buy a **PoE+ (802.3at, 30 W) injector**. The **TP-Link TL-POE260S** is the 2.5 GbE version and matches the switch's ports, so the AP links at 2.5 Gbps; the gigabit **TL-POE160S** (~$20–25) works too, but caps the AP's link at 1 Gbps.

```
cobra-switch port 6 ──► injector "LAN/Data" ──► injector "PoE" ──► AP
                        injector power cord → wall outlet (or the UPS)
```

cobra-switch also carries part 9's VLANs, so no PoE switch is planned; the injector stays.

## Shopping list

| Item | ~Price |
|---|---|
| TP-Link Omada EAP772 (or EAP723 to save ~$80) | $165 |
| TP-Link TL-POE260S (2.5 GbE) or TL-POE160S (gigabit, ~$22) PoE+ injector | $22–40 |
| Cat 6 patch cable, long enough to reach the mounting spot | $10 |
| **Total** | **~$200–215** (~$120–135 with the EAP723) |

## Sources

- ComputingForGeeks, "Best Wi-Fi 7 access points for a homelab" (prices rechecked Oct 2026): https://computingforgeeks.com/best-wifi-7-access-points-homelab/
- Dong Knows Tech, UniFi access points (standalone limits, injector not included): https://dongknows.com/best-unifi-access-points/
