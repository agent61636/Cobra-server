# cobra-hiscore

The server behind `scores.songofeo.com`. It accepts arcade `.hi` files from the cabinet agent, keeps every version, and shows an arcade-style board of every game, **newest score first**. The LaunchBox plugin adds titles and score tables; `/screen` is the big arcade screen for `songofeo.com/arcade` (manual 7.7).

- Python standard library only; no packages to install
- Runs in the `gate` pod on `127.0.0.1:8090` (manual part 7)
- Data: `/srv/gate/hiscore` on the gate. `raw/` holds every version of every file, byte for byte; `hiscore.db` is the index.

Tests: `python3 -m unittest discover -s tests` from this folder.

New API key: `python3 -m hiscore hash-key cabinet` prints a key for the agent and the line to add to `keys.txt`.
