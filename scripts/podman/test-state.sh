#!/usr/bin/env bash
# Round-trip the personal-state snapshot without podman or the real disks.
# shellcheck shell=bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export COBRA_DATA=$tmp/data
export COBRA_STATE_BACKUP=$tmp/backups
export COBRA_DISKS=$tmp/disks
export STATE_NO_TIMER=1
export STATE_SKIP_CHOWN=1
export HOME=$tmp/home
mkdir -p "$HOME" "$COBRA_DATA" "$COBRA_STATE_BACKUP"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

nd_star() {
  python3 - "$1" <<'PY'
import os, sqlite3, sys
root = os.environ["COBRA_DATA"] + "/navidrome"
os.makedirs(root, exist_ok=True)
c = sqlite3.connect(root + "/navidrome.db")
c.execute("create table if not exists annotation (user_id text, item_id text, starred int)")
c.execute("delete from annotation")
c.execute("insert into annotation values ('rachel', 'track1', ?)", (int(sys.argv[1]),))
c.commit()
PY
}

nd_read() {
  python3 - <<'PY'
import os, sqlite3
c = sqlite3.connect(os.environ["COBRA_DATA"] + "/navidrome/navidrome.db")
print(c.execute("select starred from annotation").fetchone()[0])
PY
}

latest_tar() {
  local name=$1
  echo "$COBRA_STATE_BACKUP/$name/$(tr -d '[:space:]' <"$COBRA_STATE_BACKUP/$name/LATEST")"
}

# Nothing to restore yet: an empty app stays empty and the command succeeds.
restore_state_if_empty navidrome
[ ! -e "$COBRA_DATA/navidrome/navidrome.db" ] || fail "restore invented a database"

nd_star 1
mkdir -p "$COBRA_DATA/navidrome/cache"
echo 'not-personal' >"$COBRA_DATA/navidrome/cache/big.bin"
backup_state navidrome
tar=$(latest_tar navidrome)
tar -tzf "$tar" | grep -q 'big.bin' && fail "navidrome cache was included"
tar -tzf "$tar" | grep -q 'navidrome.db' || fail "navidrome.db missing from snapshot"

# A live database is not replaced by the snapshot.
nd_star 0
restore_state_if_empty navidrome
[ "$(nd_read)" = 0 ] || fail "restore overwrote a live database"

# Wipe the instance directory. The snapshot is the starred=1 copy; the unsaved 0 is gone.
rm -rf "$COBRA_DATA/navidrome"
mkdir -p "$COBRA_DATA/navidrome"
restore_state_if_empty navidrome
[ "$(nd_read)" = 1 ] || fail "wiped navidrome did not restore the snapshot (starred=1)"
[ ! -e "$COBRA_DATA/navidrome/cache/big.bin" ] || fail "cache came back from the snapshot"

# Start blank on purpose.
rm -rf "$COBRA_DATA/navidrome"
mkdir -p "$COBRA_DATA/navidrome"
SKIP_STATE_RESTORE=1 restore_state_if_empty navidrome
[ ! -e "$COBRA_DATA/navidrome/navidrome.db" ] || fail "SKIP_STATE_RESTORE still restored"

# Retention keeps the newest STATE_KEEP snapshots, and restore reads that newest one.
export STATE_KEEP=2
rm -rf "$COBRA_STATE_BACKUP/navidrome"
mkdir -p "$COBRA_DATA/navidrome"
nd_star 7
backup_state navidrome
nd_star 8
backup_state navidrome
nd_star 9
backup_state navidrome
count=$(find "$COBRA_STATE_BACKUP/navidrome" -name '20*.tar.gz' | wc -l | tr -d ' ')
[ "$count" = 2 ] || fail "expected 2 snapshots, found $count"
rm -rf "$COBRA_DATA/navidrome"
mkdir -p "$COBRA_DATA/navidrome"
restore_state_if_empty navidrome
[ "$(nd_read)" = 9 ] || fail "restore did not use the newest snapshot"
unset STATE_KEEP

# A bad checksum must not be treated as "no snapshot" (that would start the app empty).
python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["COBRA_STATE_BACKUP"]) / "navidrome" / "LATEST"
name = p.read_text().strip()
blob = p.with_name(name)
data = bytearray(blob.read_bytes())
data[len(data)//2] ^= 0xFF
blob.write_bytes(data)
PY
rm -rf "$COBRA_DATA/navidrome"
mkdir -p "$COBRA_DATA/navidrome"
if (restore_state_if_empty navidrome); then
  fail "corrupt snapshot was restored"
fi
[ ! -e "$COBRA_DATA/navidrome/navidrome.db" ] || fail "corrupt snapshot wrote a database"

# Jellyfin: userdata comes back; the poster cache does not.
jf=$COBRA_DATA/jellyfin
mkdir -p "$jf/config/data" "$jf/config/config" "$jf/config/metadata" "$jf/config/root"
python3 - <<'PY'
import os, sqlite3
p = os.environ["COBRA_DATA"] + "/jellyfin/config/data/jellyfin.db"
c = sqlite3.connect(p)
c.execute("create table UserData (UserId text, ItemId text, IsFavorite int, PlaybackPositionTicks int)")
c.execute("insert into UserData values ('eels', 'movie-1', 1, 50)")
c.commit()
PY
echo '<NetworkConfiguration></NetworkConfiguration>' >"$jf/config/config/network.xml"
echo 'poster-bytes' >"$jf/config/metadata/poster.jpg"
backup_state jellyfin
jtar=$(latest_tar jellyfin)
tar -tzf "$jtar" | grep -q 'poster.jpg' && fail "jellyfin metadata poster was included"
tar -tzf "$jtar" | grep -q 'network.xml' || fail "jellyfin server settings were not included"
rm -rf "$jf"
mkdir -p "$jf"
restore_state_if_empty jellyfin
python3 - <<'PY'
import os, sqlite3, sys
p = os.environ["COBRA_DATA"] + "/jellyfin/config/data/jellyfin.db"
c = sqlite3.connect(p)
row = c.execute("select IsFavorite, PlaybackPositionTicks from UserData").fetchone()
if row != (1, 50):
    sys.exit("jellyfin userdata did not restore: %r" % (row,))
PY
[ ! -e "$jf/config/metadata/poster.jpg" ] || fail "jellyfin poster came back"
[ -f "$jf/config/config/network.xml" ] || fail "jellyfin network.xml did not restore"

# Audiobookshelf's files live under /srv/stream/abs, not a directory named audiobookshelf.
abs=$COBRA_DATA/abs
mkdir -p "$abs/config" "$abs/metadata/cache"
python3 - <<'PY'
import os, sqlite3
p = os.environ["COBRA_DATA"] + "/abs/config/absdatabase.sqlite"
c = sqlite3.connect(p)
c.execute("create table mediaProgress (userId text, currentTime float)")
c.execute("insert into mediaProgress values ('rachel', 12.5)")
c.commit()
PY
echo 'cache' >"$abs/metadata/cache/x"
backup_state audiobookshelf
atar=$(latest_tar audiobookshelf)
tar -tzf "$atar" | grep -q 'metadata/cache' && fail "audiobookshelf cache was included"
rm -rf "$abs"
mkdir -p "$abs"
restore_state_if_empty audiobookshelf
python3 - <<'PY'
import os, sqlite3, sys
p = os.environ["COBRA_DATA"] + "/abs/config/absdatabase.sqlite"
c = sqlite3.connect(p)
row = c.execute("select currentTime from mediaProgress").fetchone()
if row != (12.5,):
    sys.exit("audiobookshelf progress did not restore: %r" % (row,))
PY

echo "personal-state round trip ok"
