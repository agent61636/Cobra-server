# 12. Our own form service (forms.songofeo.com)

**Result:** the website forms that used to go through FormSubmit now post to our own receiver on the gate, `https://forms.songofeo.com/f/<form>`. There are three: **Advocate Change** (`voices`) and **Demand Justice** (`help`) on songofeo.com/council, and the **Cobra enlistment** (`enlist`) on hailcobra.com. Each submission is **saved on the gate first**, so none is ever lost, and then **emailed to your Gmail**, with the enlistment's filecard art attached. You can also read every saved one at `https://forms.songofeo.com/inbox`, behind your sign-in and TOTP. It's free, and it keeps working for as long as the gate runs.

**Needs:** part 5 (gate pod, nginx, Authelia, the wildcard cert, port 443 forwarded). About 30 minutes.

**What protects it:**

| Threat | What stops it |
|---|---|
| Spam bots | The hidden `_honey` box (a bot that fills it gets a fake "thanks" and nothing is saved). More than 4 links in one message goes to a spam folder and isn't emailed. |
| Flooding | nginx allows 10 posts a minute per address. The app allows 6 submissions an hour per address and 120 an hour in total. |
| Other websites using your receiver | Only the three named forms exist. Each one is accepted only from its own site (`songofeo.com` or `hailcobra.com`). Recipients are set on the gate, never in the page, so nobody can make it email someone else. |
| Bad uploads | Only the enlistment takes a file: 1 to 3 pictures, up to 6 MB, and only real JPG, PNG or WEBP (checked by content, not by name). GPS and camera data are stripped on the gate too. |
| Snooping on submissions | The inbox needs the gate sign-in plus TOTP, for `eels` only. Rachel and everyone else get "forbidden". |

**Where to do what.** Everything happens on **the-box** (the desktop): its browser, and Windows Terminal for the commands. Each command is one block. Copy it, paste it into the tab named above it, and press Enter.

---

## 12.1 Gmail app password (the-box, browser)

The gate can't send email straight from home, because Xfinity blocks outgoing mail. Gmail's own mail server does the sending for free, with an **app password**: a 16-letter password that only lets the gate send mail, and that you can cancel at any time.

Skip this section if you'd rather not have emails at all. Submissions are then only saved, and you read them at `/inbox`. In 12.4 you just press Enter when it asks for the Gmail address.

1. On the-box, open a browser tab at `https://myaccount.google.com/security` and sign in to the Gmail account that should get the emails.
2. Under **How you sign in to Google**, **2-Step Verification** must say **On**. If it's off, click it and turn it on. App passwords don't exist without it.
3. Open `https://myaccount.google.com/apppasswords` in the same tab.
4. **App name:** type `cobra-forms`, then click **Create**.
5. Google shows a 16-letter password in a yellow box. Leave that tab open. You'll paste it in 12.4. Google never shows it again, so if you close the tab, delete `cobra-forms` on that page and create a new one.

## 12.2 The forms. name (the-box, browser)

1. Open `https://porkbun.com` → **Account** → **Domain Management** → `songofeo.com` → **DNS**.
2. Add a record: **Type** `CNAME`, **Host** `forms`, **Answer** `gate.songofeo.com`, **TTL** `600`. Click **Add**.
3. Check that **URL Forwarding** for `songofeo.com` has nothing for `forms`.

You don't need to change anything at home. Pi-hole already sends every `*.songofeo.com` name to the gate (`10.6.9.10`), and OPNsense already forwards 443 to the gate.

**Only if you did the "Home DNS trick"** (OPNsense Unbound host overrides that point the app names at `10.0.0.2` for phones on Xfinity Wi-Fi): add one more override. OPNsense → **Services** → **Unbound DNS** → **Overrides** → **+**: Host `forms`, Domain `songofeo.com`, Type `A`, IP `10.0.0.2`. Click **Save**, then **Apply**.

Check the public record from the-box. Open **Windows Terminal**. A **PowerShell** tab opens, with a prompt like `PS C:\Users\...>`. Asking `1.1.1.1` directly gets around PIA's DNS:

```powershell
Resolve-DnsName forms.songofeo.com -Server 1.1.1.1
```

Expected: a `CNAME` line to `gate.songofeo.com`, then an `A` line with your home's public IP. If it says the name doesn't exist, wait 5 minutes and try again.

## 12.3 Copy the bundle to the gate (the-box, Windows Terminal, PowerShell tab)

1. Download **forms-gate.tar.gz** from the project files (`forms/forms-gate.tar.gz`) into the-box's **Downloads** folder. It holds `forms.py`, `forms.example.json`, `forms.conf` and `install-gate.sh`, the same files as `apps/forms` in this repository.
2. In the PowerShell tab (`PS C:\Users\...>`), copy it to the gate. It asks for eels' password on the gate:

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

4. Unpack it. This makes the folder `~/forms-gate`:

```bash
tar xzf forms-gate.tar.gz
```

5. Run the installer:

```bash
bash ~/forms-gate/install-gate.sh
```

It asks two things:

- **Gmail address:** type the Gmail address from 12.1 and press Enter. For no emails, just press Enter.
- **App password:** paste the 16 letters from 12.1 (right-click pastes in Windows Terminal). Nothing shows while you paste, which is normal. Press Enter.

Then it works through 5 green steps: the app files, the email settings, the `forms` container, nginx's new `forms.conf`, and one Authelia rule. It backs up anything it changes, tests nginx and Authelia before using the change, and puts the old file back if either one refuses it. It finishes with three `OK` lines:

```
    OK   https://forms.songofeo.com/health answers 200
    OK   /inbox sends strangers to the sign-in (302)
    OK   a form sent from another website is refused (403)
```

⚠️ Adding the Authelia rule restarts Authelia, which **signs everyone out once**. Everyone just signs in again.

6. Send yourself a test email (skip this if you chose no email):

```bash
podman exec forms python3 /app/forms.py test-email
```

Expected: `Test email sent to you@gmail.com.` Check the Gmail inbox on the-box, and look in **Spam** too. If it's in Spam, open it and click **Report not spam**, so the real ones land in the inbox. If you get `Username and Password not accepted` instead, the app password is wrong. Remove the saved one, run the installer again (step 5) and paste a new app password:

```bash
podman secret rm forms_smtp_pass
```

7. The installer is done. Leave podsvc:

```bash
exit
```

The prompt is `eels@cobra-gate:~$` again.

## 12.5 Look at it from the-box (browser)

1. Open `https://forms.songofeo.com/health`. The page says `ok`.
2. Open `https://forms.songofeo.com/inbox`. It sends you to the gate's sign-in. Sign in as `eels`, type the TOTP code, and you land on **Station forms** with *Nothing here yet.*

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

Reload each page with **Ctrl+F5**, so the browser doesn't use its old copy.

- [ ] `https://songofeo.com/council/` → **Advocate Change** → pick one, type `test 1`, **RAISE YOUR VOICE**. You come back to the Council with the plaque *YOUR VOICE IS HEARD*.
- [ ] Same page → **Demand Justice** → type `test 2`, your name and email → submit. The plaque says *YOUR CASE IS BEFORE THE DAIS*.
- [ ] `https://hailcobra.com/enlist.html` → fill in the required boxes, attach a small drawing → submit. You land on the thank-you page.
- [ ] Within a minute, Gmail has three emails: `[Song of Eo] Advocate Change: ...`, `[Song of Eo] Demand Justice: ...` and `[Hail Cobra] New Cobra enlistment application`, with the drawing attached. **Reply** on one of them goes to the address the sender typed.
- [ ] `https://forms.songofeo.com/inbox` lists all three, each marked **emailed**.
- [ ] From the phone **on cellular** (Wi-Fi off), send one more Advocate Change. It arrives too, which proves it works from the internet and not just from home.

## 12.8 Day to day

- **Saved submissions:** `/srv/gate/forms/data/inbox/<date-time-id>/` on the gate (`submission.json` plus any pictures), and spam in `.../data/spam/`. They're part of the gate's nightly backup (5.6). Nothing is ever deleted automatically.
- **An email that didn't go out:** the inbox shows *not sent yet* (hover it for the reason). The gate retries on its own, waiting longer each time (up to every 6 hours). To see why: as podsvc, `podman logs --tail 20 forms`.
- **Emails to a different address:** as podsvc, change `FORMS_TO=` in `/srv/gate/forms/forms.env`, then `systemctl --user restart forms`.
- **A new form** (for example on another page): add a block for it to `/srv/gate/forms/app/forms.json` with its `title`, `subject`, the site's `origins` and the `next` page to come back to, then `systemctl --user restart forms`. Its `<form>` gets `method="POST"`, `action="https://forms.songofeo.com/f/<name>"`, and the hidden `_honey` box copied from the council page. Add `"uploads": true` only if it takes pictures, and then also `enctype="multipart/form-data"` on the `<form>`.
- **"Please send this form from the website":** the page's address isn't in that form's `origins`, for example a `www.` address or a test copy. Add it to `forms.json` and restart, as above.
- **Updates:** `forms.py` is one file. For a new version, run 12.3 and 12.4 again. The installer keeps your `forms.json`, `forms.env` and app password.
- **No auto-reply to senders.** FormSubmit used to send the enlistment's "under review" email to applicants. That's off here, because it would come from your own Gmail address. The thank-you page still shows the message.

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
