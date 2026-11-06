# cobra-forms

The station's own form receiver at `forms.songofeo.com`, a free, self-hosted stand-in for FormSubmit. The website's plain HTML forms post to `https://forms.songofeo.com/f/<form>`; each submission is saved on the gate, then emailed through a Gmail app password (optional), and readable at `/inbox` behind Authelia (`eels`, password + TOTP).

- Python standard library only, one file (`forms.py`), in the `gate` pod on `127.0.0.1:8097`
- Forms: `forms.json` on the gate (start from `forms.example.json`): `voices` and `help` (songofeo.com/council), `enlist` (hailcobra.com/enlist.html, takes filecard art)
- Data: `/srv/gate/forms/data/inbox/<id>/` (`submission.json` + pictures), spam in `data/spam/`
- Gate files: `gate/forms.conf` (nginx, its own file in `conf.d`) and `gate/install-gate.sh` (Quadlet, nginx, Authelia rule; backs up and validates every change)
- Setup, step by step: [manual part 12](../../docs/manual/12-forms.md)

Hidden fields it understands: `_next` (where to send the visitor after, only on the form's own site) and `_honey` (the bot trap: filled in means dropped). `_subject`, `_template`, `_autoresponse` and `_captcha` are ignored.

Tests: `python3 -m unittest discover -s tests` from this folder.
