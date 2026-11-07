# 12. Inbox only (forms.songofeo.com, no email)

**Result:** the website forms that used to go through FormSubmit post to our own receiver on the gate, `https://forms.songofeo.com/f/<form>`. There are three: **Advocate Change** (`voices`) and **Demand Justice** (`help`) on songofeo.com/council, and the **Cobra enlistment** (`enlist`) on hailcobra.com. Each submission is **saved on the gate**, and you read it at `https://forms.songofeo.com/inbox`, behind your sign-in and TOTP (`eels` only). Email is off. There is no Gmail app password and no outbound mail. It's free, and it keeps working for as long as the gate runs.

**Needs:** part 5 (gate pod, nginx, Authelia, the wildcard cert, port 443 forwarded). About 30 minutes.

**Chosen:** November 6, 2026. This is the go-live to follow. [12-forms.md](12-forms.md) is the same service with Gmail added. Skip section 12.1 there (the Gmail app password), and skip its test-email step. The bundle is built from this repository in 12.3 below. You do not download `forms-gate.tar.gz` from project files.

**What protects it:**

| Threat | What stops it |
|---|---|
| Spam bots | The hidden `_honey` box (a bot that fills it gets a fake "thanks" and nothing is saved). More than 4 links in one message goes to a spam folder, separate from the inbox list. |
| Flooding | nginx allows 10 posts a minute per address. The app allows 6 submissions an hour per address and 120 an hour in total. |
| Other websites using your receiver | Only the three named forms exist. Each one is accepted only from its own site (`songofeo.com` or `hailcobra.com`). |
| Bad uploads | Only the enlistment takes a file: 1 to 3 pictures, up to 6 MB, and only real JPG, PNG or WEBP (checked by content, not by name). GPS and camera data are stripped on the gate too. |
| Snooping on submissions | The inbox needs the gate sign-in plus TOTP, for `eels` only. Rachel and everyone else get "forbidden". |

**Where to do what.** Everything happens on **the-box** (the desktop): its browser, and Windows Terminal for the commands. Each command is one block. Copy it, paste it into the tab named above it, and press Enter.

---

## 12.1 is not used

Do not create a Gmail app password. Do not open the Google app-passwords page. When the installer in 12.4 asks for the Gmail address, press Enter. Leave it empty. If it then asks for an app password, press Enter again, and follow the note in 12.4. A first install does not ask that second question.

## 12.2 The forms. name (the-box, browser)

1. Open `https://porkbun.com` → **Account** → **Domain Management** → `songofeo.com` → **DNS**.
2. Add a record: **Type** `CNAME`, **Host** `forms`, **Answer** `gate.songofeo.com`, **TTL** `600`. Click **Add**.
3. Check that **URL Forwarding** for `songofeo.com` has nothing for `forms`. Do not add forwarding for `forms`.

You don't need to change anything at home. Pi-hole already sends every `*.songofeo.com` name to the gate (`10.6.9.10`), and OPNsense already forwards 443 to the gate.

**Only if you did the "Home DNS trick"** (OPNsense Unbound host overrides that point the app names at `10.0.0.2` for phones on Xfinity Wi-Fi): add one more override. OPNsense → **Services** → **Unbound DNS** → **Overrides** → **+**: Host `forms`, Domain `songofeo.com`, Type `A`, IP `10.0.0.2`. Click **Save**, then **Apply**. Skip this override if you never added those host overrides.

Check the public record from the-box. Open **Windows Terminal**. A **PowerShell** tab opens, with a prompt like `PS C:\Users\...>`. Asking `1.1.1.1` directly gets around PIA's DNS:

```powershell
Resolve-DnsName forms.songofeo.com -Server 1.1.1.1
```

Expected: a `CNAME` line to `gate.songofeo.com`, then an `A` line with your home's public IP. If it says the name doesn't exist, wait 5 minutes and try again.

## 12.3 Build the bundle from this repository (the-box, Windows Terminal, PowerShell tab)

The installer only looks in its own folder. After unpacking, that folder is `~/forms-gate` on the gate, and these four files have to sit side by side in it:

| File the installer reads | Where it is in this repository |
|---|---|
| `forms.py` | `apps/forms/forms.py` |
| `forms.example.json` | `apps/forms/forms.example.json` |
| `forms.conf` | `apps/forms/gate/forms.conf` |
| `install-gate.sh` | `apps/forms/gate/install-gate.sh` |

`forms.conf` and `install-gate.sh` live under `gate/` in the repository. The bundle lifts them up next to the other two. The installer checks that `forms.py`, `forms.example.json` and `forms.conf` are readable beside the script, and stops with `missing .../forms.conf (unpack the whole bundle)` if any one is somewhere else. A zip of the whole `apps/forms` folder is the wrong shape. Tests, `README.md` and the `gate/` folder are not part of the bundle. The first run on the gate copies `forms.example.json` to `forms.json` (the three live forms). Later runs keep your `forms.json`.

The tarball has this layout, and nothing else:

```
forms-gate/
    forms.py
    forms.example.json
    forms.conf
    install-gate.sh
```

1. On the-box, in a browser, open `https://github.com/agent61636/Cobra-server` → **Code** → **Download ZIP**. In Explorer, open **Downloads**, right-click the zip, and **Extract All**. The folder is `Cobra-server-main`. A git clone of the same repository works too: use that folder instead, and the same commands from step 3 on. Either way, the folder you `cd` into is the one that contains `apps`.

2. In the PowerShell tab (`PS C:\Users\...>`), go into that folder:

```powershell
cd $HOME\Downloads\Cobra-server-main
```

3. Confirm the four source files are there. Expected: four lines, each a file, and no red errors.

```powershell
Get-ChildItem .\apps\forms\forms.py, .\apps\forms\forms.example.json, .\apps\forms\gate\forms.conf, .\apps\forms\gate\install-gate.sh
```

4. Make an empty staging folder. If you already ran this once, the remove clears the old staging folder. It does not touch `apps\forms`.

```powershell
Remove-Item -Recurse -Force .\forms-gate -ErrorAction SilentlyContinue
```

```powershell
New-Item -ItemType Directory -Path .\forms-gate
```

5. Copy the four files in flat. One copy per block:

```powershell
Copy-Item .\apps\forms\forms.py .\forms-gate\
```

```powershell
Copy-Item .\apps\forms\forms.example.json .\forms-gate\
```

```powershell
Copy-Item .\apps\forms\gate\forms.conf .\forms-gate\
```

```powershell
Copy-Item .\apps\forms\gate\install-gate.sh .\forms-gate\
```

6. Look at the staging folder. Expected: `forms.py`, `forms.example.json`, `forms.conf`, `install-gate.sh`. No `gate` subfolder.

```powershell
Get-ChildItem .\forms-gate
```

7. Pack it into **Downloads**. This is the file you copy to the gate:

```powershell
tar -czf $HOME\Downloads\forms-gate.tar.gz forms-gate
```

8. List the tarball. Expected: a `forms-gate/` line, then the same four names under it (`forms.py`, `forms.example.json`, `forms.conf`, `install-gate.sh`). Paths use forward slashes.

```powershell
tar -tf $HOME\Downloads\forms-gate.tar.gz
```

9. Remove the staging folder. The tarball in Downloads stays.

```powershell
Remove-Item -Recurse -Force .\forms-gate
```

10. Copy the tarball to the gate. It asks for eels' password on the gate:

```powershell
scp $HOME\Downloads\forms-gate.tar.gz eels@10.6.9.10:/tmp/
```

Expected: one line ending in `100%`.

## 12.4 Install it (the-box, Windows Terminal, an SSH tab on the gate)

1. Open a **new tab** in Windows Terminal (Ctrl+Shift+T). It's PowerShell again. Log in to the gate:

```powershell
ssh eels@10.6.9.10
```

The prompt becomes `eels@cobra-gate:~$`.

2. Hand the bundle to podsvc, the user that runs every container on the gate:

```bash
sudo install -o podsvc -g podsvc -m 644 /tmp/forms-gate.tar.gz /home/podsvc/
```

3. Become podsvc. Use machinectl, because `sudo su` doesn't start the session the containers need:

```bash
sudo machinectl shell podsvc@
```

The prompt becomes `podsvc@cobra-gate:~$`.

4. Unpack it. This makes the folder `~/forms-gate` with the four files side by side:

```bash
tar xzf forms-gate.tar.gz
```

```bash
ls ~/forms-gate
```

Expected: `forms.conf  forms.example.json  forms.py  install-gate.sh`. If `forms.conf` is missing, or the only extra thing is a `gate` folder, stop and rebuild the tarball with 12.3. The installer will not run until those four names are in this folder.

5. Run the installer:

```bash
bash ~/forms-gate/install-gate.sh
```

It asks:

- **Gmail address:** press Enter. Do not type an address. The line above the question says to leave it empty for no email, and to read submissions at `/inbox`. That is this setup.

A first install with an empty address does not ask for an app password. Do not paste one. There is no second question to answer.

Then it works through 5 green steps: the app files, the email settings, the `forms` container, nginx's new `forms.conf`, and one Authelia rule. It backs up anything it changes, tests nginx and Authelia before using the change, and puts the old file back if either one refuses it. Step 2 writes `/srv/gate/forms/forms.env` with `FORMS_SMTP_USER` empty, and it does not save an app password. In the lines from step 3, look for `email OFF (saving only)`. It finishes with three `OK` lines:

```
    OK   https://forms.songofeo.com/health answers 200
    OK   /inbox sends strangers to the sign-in (302)
    OK   a form sent from another website is refused (403)
```

The last line of the script can still say `Next: the email test`. Ignore that line. Do not run the test email. With this setup that command stops and prints `Email is off: FORMS_SMTP_USER or FORMS_SMTP_PASS is empty.`

⚠️ Adding the Authelia rule restarts Authelia, which **signs everyone out once**. Everyone just signs in again.

**If it asks for an app password:** press Enter again. Do not type or paste a password. The installer stops with `that was 0 letters, an app password has 16.` That question is only shown when `/srv/gate/forms/forms.env` already contains a Gmail address, so a blank Enter does not finish the install, and it does not save a password. The other apps on the gate are untouched. Move the saved address aside and run the installer again:

```bash
mv /srv/gate/forms/forms.env /srv/gate/forms/forms.env.with-mail
```

```bash
bash ~/forms-gate/install-gate.sh
```

Press Enter at **Gmail address**.

**If it never asks, and the notes say it kept the podman secret `forms_smtp_pass`:** an earlier run already stored an app password, so mail is still on. Remove that secret (the saved app password only; the submissions stay), move `forms.env` aside with the command above if that file is still there, then run the installer again and press Enter at the Gmail address:

```bash
podman secret rm forms_smtp_pass
```

6. The installer is done. Leave podsvc:

```bash
exit
```

The prompt is `eels@cobra-gate:~$` again. You can close the SSH tab, or leave it. The rest of the checks are in the browser.

## 12.5 Look at it from the-box (browser)

The three `OK` lines in 12.4 are the gate checking itself. These two are what you see from the desktop. If the browser can't find the name, wait and run the `Resolve-DnsName` command in 12.2 again.

1. Open `https://forms.songofeo.com/health`. The page says `ok`.
2. Open `https://forms.songofeo.com/inbox`. It sends you to the gate's sign-in. Sign in as `eels`, type the TOTP code, and you land on **Station forms**. Before any test, the page says *Nothing here yet.* Under the title it says **Email is off: submissions are only saved here.**

## 12.6 Point the live forms at it (the-box, browser, Porkbun's editor)

Change only the `action="..."` part of each `<form>` line, straight on the live sites, so nothing else on those pages is touched. The repositories have the same change (Project-Eo and Project-Cobra pull requests), so the next publish doesn't undo it.

**songofeo.com** (Porkbun → `songofeo.com` → **Static Hosting** → open the file editor):

1. Open `council/index.html`.
2. Ctrl+F `formsubmit.co`. There are two matches, one per `<form` line.
3. Replace the first form's `action="https://formsubmit.co/voices@songofeo.com"` with:

```
action="https://forms.songofeo.com/f/voices"
```

4. Replace the second form's `action="https://formsubmit.co/help@songofeo.com"` with:

```
action="https://forms.songofeo.com/f/help"
```

5. Ctrl+F `formsubmit.co` again. It must find nothing now. Click **Save**.

**hailcobra.com** (wherever you edit hailcobra.com live; Porkbun's editor if it's hosted there too):

1. Open `enlist.html`.
2. Ctrl+F `formsubmit.co`. There's one match, on the `<form class="panel enlist-form"` line. The address after `formsubmit.co/` may be `enlist@hailcobra.com` or a random alias; either way, replace the whole `action="https://formsubmit.co/..."` with:

```
action="https://forms.songofeo.com/f/enlist"
```

3. Ctrl+F `formsubmit.co` again. It must find nothing now. Click **Save**.

## 12.7 Test the three live forms (the-box browser, then the phone)

Reload each page with **Ctrl+F5**, so the browser doesn't use its old copy. Nothing in this test arrives by email. The inbox is the record.

- [ ] `https://songofeo.com/council/` → **Advocate Change** → pick one, type `test 1`, **RAISE YOUR VOICE**. You come back to the Council with the plaque *YOUR VOICE IS HEARD*.
- [ ] Same page → **Demand Justice** → type `test 2`, your name and email → submit. The plaque says *YOUR CASE IS BEFORE THE DAIS*.
- [ ] `https://hailcobra.com/enlist.html` → fill in the required boxes, attach a small drawing → submit. You land on the thank-you page.
- [ ] `https://forms.songofeo.com/inbox` (sign in as `eels` with the TOTP code if it asks again) lists all three: **Advocate Change**, **Demand Justice**, and **Cobra enlistment**. The enlistment row includes the picture. The line under the title still says **Email is off: submissions are only saved here.** The Email column on each row says **saved**. The rows are not marked **emailed**. Open one: under the time it says `Email: not emailed`.
- [ ] From the phone **on cellular** (Wi-Fi off), send one more Advocate Change. It shows up in the inbox too, which proves it works from the internet and not just from home.

## 12.8 Day to day

- **Saved submissions:** `/srv/gate/forms/data/inbox/<date-time-id>/` on the gate (`submission.json` plus any pictures), and spam in `.../data/spam/`. They're part of the gate's nightly backup (5.6). Nothing is ever deleted automatically. The inbox page is the way you read them.
- **Email stays off.** `/srv/gate/forms/forms.env` has an empty `FORMS_SMTP_USER`. It can still list `FORMS_SMTP_HOST=smtp.gmail.com`. That host line does nothing while the address is empty and there is no app password. Leave the address empty. The inbox column for a normal submission says **saved**. **emailed** and **not sent yet** belong to the Gmail path in [12-forms.md](12-forms.md), which this setup does not use.
- **A new form** (for example on another page): add a block for it to `/srv/gate/forms/app/forms.json` with its `title`, `subject`, the site's `origins` and the `next` page to come back to, then `systemctl --user restart forms` as podsvc. Its `<form>` gets `method="POST"`, `action="https://forms.songofeo.com/f/<name>"`, and the hidden `_honey` box copied from the council page. Add `"uploads": true` only if it takes pictures, and then also `enctype="multipart/form-data"` on the `<form>`.
- **"Please send this form from the website":** the page's address isn't in that form's `origins`, for example a `www.` address or a test copy. Add it to `forms.json` and restart, as above.
- **Updates:** `forms.py` is one file. For a new version, run 12.3 and 12.4 again. The installer keeps your `forms.json` and `forms.env`. An empty `FORMS_SMTP_USER` stays empty, so a re-run does not ask for an address and does not turn mail on.
- **No mail to senders.** The thank-you page on hailcobra.com still shows its message. Nothing is sent to the address a person types into a form.

## 12.9 Undo (as podsvc on the gate)

Nothing below deletes the saved submissions. Each step moves a file aside instead of deleting it.

```bash
systemctl --user stop forms
```

```bash
mv ~/.config/containers/systemd/forms.container ~/forms.container.off
```

```bash
mv /srv/gate/nginx/conf.d/forms.conf /srv/gate/nginx/forms.conf.off
```

```bash
podman exec nginx nginx -s reload
```

```bash
systemctl --user daemon-reload
```

The Authelia rule for `forms.songofeo.com` does nothing without the nginx file, so it can stay. To take it out too, copy back the backup the installer printed in step 5/5 (`configuration.yml.bak-<date>`) and run `systemctl --user restart authelia`.
