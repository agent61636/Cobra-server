# Cobra hiscore agent (cabinet)

Runs on `cobra-arcade` as the `arcade` user. Every 15 seconds it checks the RetroArch folders in `config.json` for `*.hi` files. Any file that changed, and has been still for 5 seconds, is uploaded to `https://scores.songofeo.com/upload/<system>/<file>` with the cabinet's API key.

- `<system>` is the first folder under each watched path, so `saves\fbneo\…\galaga.hi` is `fbneo/galaga.hi`. Set `"system"` in `config.json` to name a folder's system yourself.
- Failed uploads are retried on the next pass. A file only counts as sent once the server has accepted it, so a network or server outage loses nothing.
- The key is stored in `key.dat`, encrypted with Windows DPAPI for the `arcade` user.
- Windows PowerShell 5.1 (built into Windows 11). Nothing to install.

Install (plain, non-admin PowerShell as `arcade`, from this folder): `.\install.ps1`. See manual part 7.

Tested end to end against the server (PowerShell 7.4): new files, unchanged files, files still being written, wrong key, server down then back.
