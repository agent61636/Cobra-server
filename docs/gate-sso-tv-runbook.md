# Gate sign-in and TV apps: check, then fix

Goal: the gate's sign-in (Authelia) works everywhere, friends sign in to the TV and phone apps with
their own app username and password, and your TV on the Xfinity router and your phone on home Wi-Fi
(Electronomicon) reach every name.

The config text in manual 5.4 was tested again on 2026-11-07 in throwaway containers (nginx stable,
Authelia latest), with the N.A.V. wall on `mustang.`:

| Test | Result |
|---|---|
| `authelia validate-config`, `nginx -t` | no errors |
| Not signed in: `music.` `mustang.` `comedy.` `sessions.` `books.` `comics.` `arcade.` `gaming.` `vip.` `papers.` `command.` | 302 to `gate.songofeo.com` |
| Not signed in: `tv.` | straight to Jellyfin, no gate sign-in |
| Phone-app paths (`/rest/` on every Navidrome, ABS `/api/` and `/login`, `/api/` on Kavita and Paperless) | reach the app, and a forged `Remote-User: eels` header is dropped |
| `/rest/%2e%2e/app/` (a sneaky path) | 302 to the sign-in |
| Signed in as eels / rachel / sam | each app gets that username and display name; `mustang.` refuses sam (403); `vip.` sends eels to `music.` and rachel to `mustang.`; `papers.` still asks for TOTP |

So when something fails on the real gate, it's the gate's *state* (which one-shot scripts ran) or the
network, not the config text. Step 1 finds out which.

## Step 1. Read-only check on the gate (changes nothing)

On **the-box**, open **Windows Terminal** → a **PowerShell** tab, `cd` to the folder you downloaded
`gate-sso-check.sh` into (from the project files, `gate/`), and copy it to the gate:

```powershell
scp .\gate-sso-check.sh eels@10.6.9.10:/tmp/
```

Then SSH to the gate in the same tab. The prompt becomes `eels@cobra-gate:~$`:

```powershell
ssh eels@10.6.9.10
```

Install it in podsvc's home (podsvc owns the containers, so the check has to run as podsvc):

```bash
sudo install -o podsvc -m 755 /tmp/gate-sso-check.sh /home/podsvc/
```

Run it as podsvc:

```bash
sudo machinectl shell podsvc@ /bin/bash /home/podsvc/gate-sso-check.sh
```

It prints OK, NOTE or FAIL lines in four groups: the containers, Authelia's config, nginx's config,
and live answers from nginx. Send Claude everything from `== 1.` down.

## Step 2. Fixes, only for the FAIL lines

Each FAIL line names the one-shot script that fixes it. Every one-shot backs up the file it changes
(`*.bak-YYYYmmdd-HHMMSS`), checks the result with `nginx -t` or `authelia validate-config`, and puts
the backup back if the check fails. Running one twice changes nothing. Run them in this order:

| FAIL says | Script (in `scripts/oneshot/`, copies in the project files) | What it changes |
|---|---|---|
| `mustang. port`, `rule for comedy.`, `server block for comedy.` / `sessions.` | `gate-navidromes.sh` | nginx and Authelia: the four Navidromes |
| `home bypass` | `gate-signin.sh` | Authelia only: one sign-in for everyone, Remember me = 1 month. **Signs everyone out once** |
| `phone-app paths`, `/rest/ (apps)` sent to the sign-in, `books. /ping` | `gate-apps.sh` | nginx only: the apps' API paths skip the sign-in |

Copy and run each one the same way as the check (the `scp`, `install` and `machinectl` lines, with
the script's name). Then run the check from step 1 again until there are no FAIL lines.

If any `/rest/` line says **DANGER**, stop and tell Claude: it would mean a header a visitor sent
reached Navidrome.

## Step 3. The apps' own logins (what the TV and phone apps use)

**Jellyfin** (TV apps). On the-box, open `https://tv.songofeo.com` in the browser, sign in as eels,
then Dashboard:

- [ ] Dashboard → Networking → **Known proxies** is `10.6.9.10`. Without it every viewer looks like the gate.
- [ ] Dashboard → Networking → **Allow remote connections to this server** is on. With Known proxies
      set, friends outside and your Xfinity-side TV count as *remote*, so with this off they're refused.
- [ ] Dashboard → Networking → **LAN networks** is `10.6.9.0/24, 10.6.99.0/24`. Optional: add
      `10.0.0.0/24` so the TV on the Xfinity router counts as home (no remote bitrate cap).
- [ ] Dashboard → Users → each friend: their own user, strong password, **not** administrator,
      **Allow remote connections to this server** ticked, **Maximum number of failed login attempts** set (e.g. 5).
- [ ] In the friend's TV app: server `https://tv.songofeo.com` (no port), then their Jellyfin username and password.

**Navidrome** (Subsonic phone apps such as Symphonium, DSub, Substreamer). In the browser the gate
signs you in, but a phone app sends the app's own username and password on `/rest/`. A user that
Navidrome made automatically from the gate sign-in has a random password, so set one:

- [ ] `https://music.songofeo.com` as eels → the user menu (top right) → Users → the person → set a password.
- [ ] In the phone app: server `https://music.songofeo.com` (or `mustang.`, `comedy.`, `sessions.`), that username and password.

**Audiobookshelf / Kavita**: their apps use the app's own login on `https://books.songofeo.com` and
`https://comics.songofeo.com`.

## Step 4. The TV on the Xfinity router and your phone on Electronomicon

Why these fail today: a device on the Xfinity side (`10.0.0.x`) looks up `tv.songofeo.com`, gets your
public address, and the Xfinity router can't send traffic to its own public address back inside (no
NAT loopback). The fix is the "Home DNS trick": OPNsense's own DNS (Unbound) answers the station's
names with OPNsense's Xfinity-side address `10.0.0.2`, and the existing port forward 443 → gate does
the rest. Nothing changes on the Xfinity router, so the work laptop is untouched.

### 4a. Look first (read-only), on the-box's browser at `https://10.6.9.1`

- [ ] **Interfaces → [WAN] → Block private networks.** Write down whether it's ticked. Ticked means
      OPNsense drops *every* new connection that comes from `10.0.0.x`, so the TV and phone can't
      reach port 443 or 53 (nor the phone's "home" WireGuard profile at `10.0.0.2:51820`). Leave
      **Block bogon networks** as it is.
- [ ] **Firewall → NAT → Port Forward**, the 443 → `10.6.9.10` rule: **Destination** must be
      **WAN address** (that covers both the public IP and `10.0.0.2`). A single typed-in public IP
      would miss the Xfinity side.
- [ ] **Firewall → Rules → WAN**: "Allow 443 to gate" has **Source: any**.
- [ ] **Services → Unbound DNS → General → Network Interfaces**: *All* or a list. Note which.
- [ ] **Services → Unbound DNS → Overrides**: note any `songofeo.com` host overrides already there.

From the-box's PowerShell (the-box is on the LAN, so this asks Unbound directly):

```powershell
Resolve-DnsName tv.songofeo.com -Server 10.0.0.2 -DnsOnly
```

Today this should print your public address (or time out if Unbound doesn't listen there). Also note
what the-box itself gets through Pi-hole; it must stay `10.6.9.10` after step 4b. If PIA is
connected on the-box it answers instead of Pi-hole, so disconnect PIA for this test:

```powershell
Resolve-DnsName tv.songofeo.com -DnsOnly
```

### 4b. Change (send Claude the 4a results first)

1. **Interfaces → [WAN]**: untick **Block private networks** → Save → Apply. (Xfinity's DMZ only
   forwards internet traffic with internet source addresses, so this only lets in `10.0.0.x`.)
2. **Firewall → Rules → WAN → Add**: Action Pass, Interface WAN, Protocol **TCP/UDP**, Source
   **Single host or Network `10.0.0.0/24`**, Destination **This Firewall**, Destination port **DNS (53)**,
   Description `Xfinity side DNS` → Save → Apply. Only `10.0.0.x` may ask; the internet can't.
3. **Services → Unbound DNS → General → Network Interfaces**: if it's a list, add **WAN**. Save → Apply.
4. **Services → Unbound DNS → Overrides → Hosts → Add**, one per name, Domain `songofeo.com`, Type A,
   IP `10.0.0.2`: `gate`, `tv`, `music`, `mustang`, `comedy`, `sessions`, `books`, `comics`, `arcade`,
   `gaming`, `papers`, `metube`, `command`, `forms` (and `vip` once it exists). **Not** a `*` wildcard,
   because Pi-hole forwards `www.` and `vpn.` here. Not `vault`/`status`: those are LAN-only. Apply.
5. Check again from the-box. The first must now print `10.0.0.2`, the second still `10.6.9.10`:

```powershell
Resolve-DnsName tv.songofeo.com -Server 10.0.0.2 -DnsOnly
```

```powershell
Resolve-DnsName tv.songofeo.com -DnsOnly
```

If the second one turned into `10.0.0.2`, Pi-hole forwards that name to Unbound: tell Claude before
going on, because LAN devices would then hit OPNsense's own web page instead of the gate.

### 4c. The devices on the Xfinity side

- **TV**: Network settings → DNS → manual → `10.0.0.2`, and no second DNS server (a second public one
  gets used at random and gives the public address, which fails). Some TVs only allow manual DNS
  with a manual IP: then pick an address Xfinity's DHCP won't hand out, or reserve it in the Xfinity
  app. **Roku can't set DNS at all**: a Roku would need a cable to the cobra switch instead.
- **Phone on Electronomicon** (Android): Wi-Fi → Electronomicon → Edit → Advanced → IP settings
  **Static**, an address reserved in the Xfinity app, gateway `10.0.0.1`, DNS 1 `10.0.0.2`, DNS 2 empty.
  Settings → Private DNS must be **Off** or **Automatic** (a named provider skips `10.0.0.2`).
- Xfinity's router keeps handing out its own DNS to everything else, so the work laptop and the rest
  of the house are unaffected.

## Step 5. Tests

- [ ] the-box browser, private window: `https://music.songofeo.com` → gate sign-in → back in Navidrome as eels.
- [ ] the-box: `https://tv.songofeo.com` → Jellyfin's own login, no gate sign-in.
- [ ] Phone on **cellular**: Jellyfin app with a friend's account at `https://tv.songofeo.com`; a
      Subsonic app at `https://music.songofeo.com` with a Navidrome password.
- [ ] TV on the **Xfinity router**: Jellyfin app at `https://tv.songofeo.com` signs in; Dashboard →
      Activity shows the TV's `10.0.0.x` address.
- [ ] Phone on **Electronomicon** with WireGuard off: the Jellyfin app and `https://music.songofeo.com` in the browser.
- [ ] Run the step 1 check once more: no FAIL lines.
