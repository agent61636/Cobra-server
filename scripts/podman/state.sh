# shellcheck shell=bash
# Personal state: favorites, stars, playlists, watch/listen progress, bookmarks,
# per-user settings. Sourced by lib.sh. Never run this file on its own.
#
# Rerunning an app script removes the container and mounts the same folder again,
# so a restart keeps this state. A wipe of that folder does not. These functions
# copy it somewhere a wipe of /srv/stream/<app> or /srv/gate/<app> does not reach,
# and put it back when the app's own database file is missing.
#
#   SGIN snapshots: /srv/storage/vault/personal-state   (not on the Samba share)
#   Gate snapshots: /srv/backups/personal-state         (not under /srv/gate)
#   COBRA_STATE_BACKUP  overrides the directory (tests)
#   SKIP_STATE_RESTORE=1   do not fill an empty app from a snapshot
#   FORCE_STATE_RESTORE=1  only honored by state-restore.sh: move the live dir aside first
#   STATE_KEEP=14          how many snapshots to keep per app
#   STATE_NO_TIMER=1       state-backup.sh does not install the daily timer
#   STATE_SKIP_CHOWN=1     do not podman-unshare chown on restore (tests)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  printf 'ERROR: source this file. Run sgin/state-backup.sh or gate/state-backup.sh.\n' >&2
  exit 1
fi

state_app_names() {
  case $1 in
    sgin) printf '%s\n' jellyfin navidrome audiobookshelf kavita romm ersatztv radio cobra-breaks ;;
    gate) printf '%s\n' authelia vaultwarden paperless metube homepage uptime-kuma hiscore eo-art ;;
    *) return 1 ;;
  esac
}

state_load() {
  local name=$1
  STATE_NAME=$name
  STATE_CONTAINER=$name
  STATE_DB=files
  STATE_NOTES=
  case $name in
    jellyfin|navidrome|audiobookshelf|kavita|romm|ersatztv|radio|cobra-breaks)
      STATE_HOST=sgin
      STATE_BASE=${COBRA_DATA:-/srv/stream}
      ;;
    authelia|vaultwarden|paperless|metube|homepage|uptime-kuma|hiscore|eo-art)
      STATE_HOST=gate
      STATE_BASE=${COBRA_DATA:-/srv/gate}
      ;;
    *) die "no personal-state entry for $name" ;;
  esac
  case $name in
    audiobookshelf) STATE_DATA=$STATE_BASE/abs ;;
    *) STATE_DATA=$STATE_BASE/$name ;;
  esac
  # Paperless and its Postgres sit next to each other under the gate data root.
  if [ "$name" = paperless ]; then
    STATE_TAR_ROOT=$STATE_BASE
  else
    STATE_TAR_ROOT=$STATE_DATA
  fi
}

state_marker_file() {
  case $STATE_NAME in
    jellyfin)
      if [ -f "$STATE_DATA/config/data/jellyfin.db" ]; then
        printf '%s\n' "$STATE_DATA/config/data/jellyfin.db"
      elif [ -f "$STATE_DATA/config/data/library.db" ]; then
        printf '%s\n' "$STATE_DATA/config/data/library.db"
      fi
      ;;
    navidrome) printf '%s\n' "$STATE_DATA/navidrome.db" ;;
    audiobookshelf)
      if [ -f "$STATE_DATA/config/absdatabase.sqlite" ]; then
        printf '%s\n' "$STATE_DATA/config/absdatabase.sqlite"
      elif [ -f "$STATE_DATA/config/audiobookshelf.sqlite" ]; then
        printf '%s\n' "$STATE_DATA/config/audiobookshelf.sqlite"
      fi
      ;;
    kavita) printf '%s\n' "$STATE_DATA/kavita.db" ;;
    romm) printf '%s\n' "$STATE_DATA/db/ibdata1" ;;
    ersatztv) find "$STATE_DATA" -type f \( -name '*.db' -o -name '*.sqlite' \) -print -quit 2>/dev/null || true ;;
    radio) printf '%s\n' "$STATE_DATA/radio.liq" ;;
    cobra-breaks) find "$STATE_DATA" -mindepth 1 -type f ! -path '*/.cobra-restore/*' -print -quit 2>/dev/null || true ;;
    vaultwarden) printf '%s\n' "$STATE_DATA/db.sqlite3" ;;
    paperless) printf '%s\n' "$STATE_BASE/postgres/PG_VERSION" ;;
    metube) find "$STATE_DATA" -mindepth 1 -type f ! -path '*/tmp/*' ! -path '*/.cobra-restore/*' -print -quit 2>/dev/null || true ;;
    homepage) printf '%s\n' "$STATE_DATA/settings.yaml" ;;
    uptime-kuma) printf '%s\n' "$STATE_DATA/kuma.db" ;;
    hiscore) printf '%s\n' "$STATE_DATA/hiscore.db" ;;
    authelia) printf '%s\n' "$STATE_DATA/db.sqlite3" ;;
    eo-art)
      if [ -f "$STATE_DATA/eo_art.py" ]; then printf '%s\n' "$STATE_DATA/eo_art.py"
      elif [ -f "$STATE_DATA/folders.json" ]; then printf '%s\n' "$STATE_DATA/folders.json"
      fi
      ;;
    *) return 1 ;;
  esac
}

state_present() {
  local f
  f=$(state_marker_file || true)
  [ -n "$f" ] && [ -e "$f" ]
}

state_root_path() {
  local host=$1
  if [ -n "${COBRA_STATE_BACKUP:-}" ]; then
    printf '%s\n' "$COBRA_STATE_BACKUP"
    return 0
  fi
  case $host in
    sgin) printf '%s\n' /srv/storage/vault/personal-state ;;
    gate) printf '%s\n' /srv/backups/personal-state ;;
    *) die "no personal-state directory for $host" ;;
  esac
}

# ready: we can write snapshots. unmounted: the SGIN vault isn't there, so an empty
# app must not start blank and throw the snapshot away. unset: the gate directory
# was never created (first install, nothing to restore).
state_root_status() {
  local host=$1
  if [ -n "${COBRA_STATE_BACKUP:-}" ]; then
    printf '%s\n' ready
    return 0
  fi
  case $host in
    sgin)
      if mountpoint -q /srv/storage/vault 2>/dev/null; then
        printf '%s\n' ready
      else
        printf '%s\n' unmounted
      fi
      ;;
    gate)
      if [ -d /srv/backups/personal-state ]; then
        printf '%s\n' ready
      else
        printf '%s\n' unset
      fi
      ;;
    *) return 1 ;;
  esac
}

state_root_hint() {
  case $1 in
    unmounted)
      printf '%s\n' "/srv/storage/vault isn't mounted. Personal-state snapshots live there, off the Samba share (part 13)."
      ;;
    unset)
      printf '%s\n' "/srv/backups/personal-state doesn't exist yet. As eels: sudo mkdir -p /srv/backups/personal-state && sudo chown $(id -un): /srv/backups /srv/backups/personal-state"
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

state_prepare_dest() {
  local root
  root=$(state_root_path "$STATE_HOST")
  STATE_DEST=$root/$STATE_NAME
  mkdir -p "$STATE_DEST" 2>/dev/null || {
    STATE_DEST_ERR="can't create $STATE_DEST as $(id -un). As eels: sudo mkdir -p $root && sudo chown $(id -un): $root"
    warn "$STATE_DEST_ERR"
    return 1
  }
  chmod 700 "$root" "$STATE_DEST" 2>/dev/null || true
}

stat_owner() {
  local f=$1
  if [ -z "$f" ] || [ ! -e "$f" ]; then
    printf '%s\n' "0:0"
    return 0
  fi
  if command -v podman >/dev/null 2>&1 && podman unshare stat -c '%u:%g' "$f" >/dev/null 2>&1; then
    podman unshare stat -c '%u:%g' "$f"
  else
    stat -c '%u:%g' "$f"
  fi
}

# Postgres (uid 999 inside its container) and Paperless are different users. The owner
# stamped on a Paperless snapshot is a file under paperless/data, not PG_VERSION.
state_owner() {
  local f
  if [ "$STATE_NAME" = paperless ]; then
    f=$(find "$STATE_DATA/data" -type f -print -quit 2>/dev/null || true)
    stat_owner "$f"
    return 0
  fi
  f=$(state_marker_file || true)
  stat_owner "$f"
}

# Consistent SQLite copy. A plain cp of a live database can land between the file and its WAL.
sqlite_consistent() {
  local src=$1 dest=$2
  local -a cmd
  mkdir -p "$(dirname "$dest")"
  rm -f "$dest"
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 isn't installed; copying $src directly (a live database may be mid-write)"
    cp -a "$src" "$dest" || return 1
    [ -f "$src-wal" ] && cp -a "$src-wal" "$dest-wal"
    return 0
  fi
  if [ -r "$src" ]; then
    cmd=(python3)
  elif command -v podman >/dev/null 2>&1 && podman unshare test -r "$src" 2>/dev/null; then
    cmd=(podman unshare python3)
  else
    warn "can't read $src"
    return 1
  fi
  "${cmd[@]}" -c '
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
s = sqlite3.connect(src, timeout=60)
d = sqlite3.connect(dst)
s.backup(d)
d.close()
s.close()
' "$src" "$dest"
}

# Copy a tree, then rewrite every SQLite file with the backup API. Extra args are tar excludes.
stage_tree() {
  local src=$1 dest=$2
  shift 2
  [ -d "$src" ] || return 0
  mkdir -p "$dest"
  local -a tar_args=(
    --exclude=./.cobra-restore
    --exclude='*.db-wal' --exclude='*.db-shm'
    --exclude='*.sqlite-wal' --exclude='*.sqlite-shm'
    --exclude='*.sqlite3-wal' --exclude='*.sqlite3-shm'
  )
  local ex
  for ex in "$@"; do
    tar_args+=(--exclude="$ex")
  done
  tar -C "$src" "${tar_args[@]}" -cf - . | tar -C "$dest" -xf - || return 1
  local db rel failed=0
  while IFS= read -r -d '' db; do
    rel=${db#"$dest"/}
    rm -f "$dest/$rel"
    sqlite_consistent "$src/$rel" "$dest/$rel" || failed=1
  done < <(find "$dest" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0)
  [ "$failed" = 0 ]
}

state_save_secrets() {
  local name value
  command -v podman >/dev/null 2>&1 || return 0
  : >"$STAGE/import/secrets.env"
  chmod 600 "$STAGE/import/secrets.env"
  for name in "$@"; do
    podman secret exists "$name" 2>/dev/null || continue
    value=$(podman secret inspect --showsecret --format '{{.SecretData}}' "$name")
    printf '%s=%s\n' "$name" "$value" >>"$STAGE/import/secrets.env"
  done
  if [ ! -s "$STAGE/import/secrets.env" ]; then
    rm -f "$STAGE/import/secrets.env"
  fi
}

fill_jellyfin() {
  stage_tree "$STATE_DATA/config" "$STAGE/payload/config" ./metadata ./log ./logs ./cache || return 1
  STATE_DB=sqlite
  STATE_NOTES="Favorites, played, resume position, users and display preferences are in config/data (jellyfin.db; older servers also have library.db). Server settings and library folders are config/ and root/. Plugins are included. Posters (metadata/) and the cache mount are not."
}

fill_navidrome() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./cache || return 1
  STATE_DB=sqlite
  STATE_NOTES="One navidrome.db for every person. Stars, ratings and play counts are the annotation table; playlists are playlist and playlist_tracks; long-track positions are bookmark; who may see which library is user_library (Rachel's shelf is a row, not a second container). The music files stay on dock1a and are not in this snapshot."
}

fill_audiobookshelf() {
  local db found=0
  mkdir -p "$STAGE/payload/config"
  for db in absdatabase.sqlite audiobookshelf.sqlite; do
    if [ -f "$STATE_DATA/config/$db" ]; then
      sqlite_consistent "$STATE_DATA/config/$db" "$STAGE/payload/config/$db" || return 1
      found=1
    fi
  done
  [ "$found" = 1 ] || return 1
  if [ -d "$STATE_DATA/metadata/items" ]; then
    stage_tree "$STATE_DATA/metadata/items" "$STAGE/payload/metadata/items" || return 1
  fi
  if [ -d "$STATE_DATA/metadata/authors" ]; then
    stage_tree "$STATE_DATA/metadata/authors" "$STAGE/payload/metadata/authors" || return 1
  fi
  STATE_DB=sqlite
  STATE_NOTES="Users, library assignments, listening and ebook progress (mediaProgress) and bookmarks (JSON on the user) are in the sqlite file. metadata/items and metadata/authors are the covers and edited metadata those ids point at. Cache, logs and Audiobookshelf's own backup zips under metadata/backups are not included: those zips sit inside the instance directory, so a wipe deletes them too."
}

fill_kavita() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./logs ./cache ./covers || return 1
  STATE_DB=sqlite
  STATE_NOTES="kavita.db holds reading progress, bookmarks, collections, ratings and per-user preferences. appsettings.json holds the server token; restoring the database without it logs everyone out. Bookmark images are included. The cover cache is not."
}

db_wait_romm() {
  local i
  for i in $(seq 60); do
    [ "$(podman inspect -f '{{.State.Health.Status}}' romm-db 2>/dev/null || true)" = healthy ] && return 0
    podman healthcheck run romm-db >/dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

db_wait_postgres() {
  local i
  for i in $(seq 60); do
    podman exec postgres pg_isready -q -U paperless 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

fill_romm() {
  if [ -d "$STATE_DATA/assets" ]; then
    stage_tree "$STATE_DATA/assets" "$STAGE/payload/assets" || return 1
  fi
  if [ -d "$STATE_DATA/config" ]; then
    stage_tree "$STATE_DATA/config" "$STAGE/payload/config" || return 1
  fi
  state_save_secrets romm-db-password romm-db-root-password romm-auth-secret || return 1
  local started=0
  if command -v podman >/dev/null 2>&1 && podman container exists romm-db 2>/dev/null; then
    if [ "$(podman inspect -f '{{.State.Running}}' romm-db 2>/dev/null || echo false)" != true ]; then
      podman start romm-db >/dev/null || return 1
      started=1
    fi
    if ! db_wait_romm; then
      if [ "$started" = 1 ]; then podman stop romm-db >/dev/null 2>&1 || true; fi
      warn "MariaDB didn't become healthy; RomM was not snapshotted"
      return 1
    fi
    if ! podman exec romm-db sh -c 'exec mariadb-dump -u romm -p"$MARIADB_PASSWORD" --single-transaction --routines --triggers romm' >"$STAGE/import/dump.sql"; then
      rm -f "$STAGE/import/dump.sql"
      if [ "$started" = 1 ]; then podman stop romm-db >/dev/null 2>&1 || true; fi
      return 1
    fi
    if [ "$started" = 1 ]; then
      podman stop romm-db >/dev/null 2>&1 || warn "started romm-db for the dump and couldn't stop it"
    fi
    grep -q -e 'CREATE TABLE' -e 'MariaDB dump' "$STAGE/import/dump.sql" || return 1
    chmod 600 "$STAGE/import/dump.sql"
    STATE_DB=sql
    STATE_NOTES="MariaDB dump: accounts, collections, per-user save metadata. assets/: the save files and save states (per user, under users/). config.yml. Cover art in resources/ and the Redis queue are not included. ROM files stay on dock1b. Podman secrets that open this database are in the snapshot and are restored only if the host no longer has them."
  elif [ -f "$STATE_DATA/db/ibdata1" ]; then
    stage_tree "$STATE_DATA/db" "$STAGE/payload/db" || return 1
    STATE_DB=cold-datadir
    STATE_NOTES="romm-db was not on this machine, so this is a copy of the MariaDB data directory rather than a dump. Restore it with the same podman secrets."
  else
    return 1
  fi
}

fill_ersatztv() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./logs ./cache ./.cache ./transcode || return 1
  STATE_DB=sqlite
  STATE_NOTES="Channel lineup, schedules and the Jellyfin API key. Viewer progress for those channels is Jellyfin's, not this database."
}

fill_radio() {
  cp -a "$STATE_DATA/radio.liq" "$STAGE/payload/radio.liq" || return 1
  STATE_DB=files
  STATE_NOTES="Liquidsoap script only. Icecast has no data directory; its passwords are podman secrets and stay in podman's store, which a wipe of this directory does not remove."
}

fill_cobra_breaks() {
  stage_tree "$STATE_DATA" "$STAGE/payload" || return 1
  STATE_DB=files
  STATE_NOTES="breaks.toml and the Jellyfin API key. Who has watched which episode is Jellyfin's database, not this folder. There is no podman script for cobra-breaks: restore with state-restore.sh, then start the Quadlet."
}

fill_vaultwarden() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./icon_cache ./tmp ./logs || return 1
  STATE_DB=sqlite
  STATE_NOTES="The whole vault: db.sqlite3 plus attachments and the RSA keys. Icon cache is not included."
}

fill_paperless() {
  if [ -d "$STATE_DATA/data" ]; then
    stage_tree "$STATE_DATA/data" "$STAGE/payload/paperless/data" ./log ./logs || return 1
  fi
  state_save_secrets paperless-db-password paperless-secret-key || return 1
  local started=0
  if command -v podman >/dev/null 2>&1 && podman container exists postgres 2>/dev/null; then
    if [ "$(podman inspect -f '{{.State.Running}}' postgres 2>/dev/null || echo false)" != true ]; then
      podman start postgres >/dev/null || return 1
      started=1
    fi
    if ! db_wait_postgres; then
      if [ "$started" = 1 ]; then podman stop postgres >/dev/null 2>&1 || true; fi
      warn "Postgres didn't become ready; Paperless was not snapshotted"
      return 1
    fi
    if ! podman exec postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" exec pg_dump -U paperless --no-owner --no-acl paperless' >"$STAGE/import/dump.sql"; then
      rm -f "$STAGE/import/dump.sql"
      if [ "$started" = 1 ]; then podman stop postgres >/dev/null 2>&1 || true; fi
      return 1
    fi
    if [ "$started" = 1 ]; then
      podman stop postgres >/dev/null 2>&1 || warn "started postgres for the dump and couldn't stop it"
    fi
    grep -q -e 'CREATE TABLE' -e 'PostgreSQL database dump' "$STAGE/import/dump.sql" || return 1
    chmod 600 "$STAGE/import/dump.sql"
    STATE_DB=sql
    STATE_NOTES="Users, saved views, tags, correspondents and the document index. paperless/data is the search index. The originals in paperless/media are not in this snapshot (the gate disk is 64 GB; copying them beside themselves can fill it). They stay in /srv/gate/paperless/media and in the nightly VM backup. Redis is a queue and is not included."
  elif [ -f "$STATE_BASE/postgres/PG_VERSION" ]; then
    stage_tree "$STATE_BASE/postgres" "$STAGE/payload/postgres" || return 1
    STATE_PG_OWNER=$(stat_owner "$STATE_BASE/postgres/PG_VERSION")
    STATE_DB=cold-postgres
    STATE_NOTES="Postgres was not running, so this is a copy of its data directory. The originals in paperless/media are not included."
  else
    return 1
  fi
}

fill_metube() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./tmp || return 1
  STATE_DB=files
  STATE_NOTES="Download queue and history. Finished videos stay on wd2/youtube and are not in this snapshot."
}

fill_homepage() {
  stage_tree "$STATE_DATA" "$STAGE/payload" || return 1
  STATE_DB=files
  STATE_NOTES="The dashboard yaml (one board, not one per person)."
}

fill_uptime_kuma() {
  stage_tree "$STATE_DATA" "$STAGE/payload" ./logs || return 1
  STATE_DB=sqlite
  STATE_NOTES="Monitors, notification settings and the Kuma user, in kuma.db."
}

fill_hiscore() {
  stage_tree "$STATE_DATA" "$STAGE/payload" || return 1
  STATE_DB=sqlite
  STATE_NOTES="hiscore.db, the raw .hi files and keys.txt. The app code under hiscore-app is not included; hiscore.sh copies it from the repo."
}

fill_authelia() {
  local f
  mkdir -p "$STAGE/payload"
  for f in configuration.yml users.yml; do
    [ -f "$STATE_DATA/$f" ] || continue
    cp -a "$STATE_DATA/$f" "$STAGE/payload/$f" || return 1
  done
  [ -f "$STATE_DATA/db.sqlite3" ] || return 1
  sqlite_consistent "$STATE_DATA/db.sqlite3" "$STAGE/payload/db.sqlite3" || return 1
  STATE_DB=sqlite
  STATE_NOTES="users.yml (password hashes), db.sqlite3 (TOTP devices) and configuration.yml, because the database is encrypted with the key in that file. notification.txt is not included. The files are copied as they are; this does not change access rules."
}

fill_eo_art() {
  stage_tree "$STATE_DATA" "$STAGE/payload" || return 1
  STATE_DB=files
  STATE_NOTES="eo_art.py and folders.json. The pictures themselves stay on dock1a and are not in this snapshot."
}

fill_state() {
  local rc=0
  case $STATE_NAME in
    jellyfin) fill_jellyfin || rc=1 ;;
    navidrome) fill_navidrome || rc=1 ;;
    audiobookshelf) fill_audiobookshelf || rc=1 ;;
    kavita) fill_kavita || rc=1 ;;
    romm) fill_romm || rc=1 ;;
    ersatztv) fill_ersatztv || rc=1 ;;
    radio) fill_radio || rc=1 ;;
    cobra-breaks) fill_cobra_breaks || rc=1 ;;
    vaultwarden) fill_vaultwarden || rc=1 ;;
    paperless) fill_paperless || rc=1 ;;
    metube) fill_metube || rc=1 ;;
    homepage) fill_homepage || rc=1 ;;
    uptime-kuma) fill_uptime_kuma || rc=1 ;;
    hiscore) fill_hiscore || rc=1 ;;
    authelia) fill_authelia || rc=1 ;;
    eo-art) fill_eo_art || rc=1 ;;
    *) die "no snapshot method for $STATE_NAME" ;;
  esac
  [ "$rc" = 0 ] || return 1
  if [ -s "$STAGE/import/dump.sql" ]; then
    return 0
  fi
  [ -n "$(find "$STAGE/payload" -type f -print -quit)" ]
}

state_prune() {
  local dest=$1 keep=${STATE_KEEP:-14}
  local -a files=()
  local n i
  mapfile -t files < <(find "$dest" -maxdepth 1 -type f -name '20*.tar.gz' | sort)
  n=${#files[@]}
  for ((i = 0; i < n - keep; i++)); do
    rm -f "${files[$i]}" "${files[$i]}.sha256"
  done
}

state_pack() {
  local dest=$1 stamp tar
  stamp=$(date -u +%Y%m%dT%H%M%S%NZ)
  while [ -e "$dest/$stamp.tar.gz" ]; do stamp=${stamp}x; done
  tar=$dest/$stamp.tar.gz
  {
    echo "app: $STATE_NAME"
    echo "host: $STATE_HOST"
    echo "taken: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "owner: ${STATE_OWNER}"
    if [ -n "${STATE_PG_OWNER:-}" ]; then
      echo "pg_owner: ${STATE_PG_OWNER}"
    fi
    echo "db: ${STATE_DB}"
    echo "notes: ${STATE_NOTES}"
  } >"$STAGE/MANIFEST"
  chmod 600 "$STAGE/MANIFEST"
  mkdir -p "$STAGE/import"
  tar -C "$STAGE" -czf "$tar" MANIFEST payload import || return 1
  chmod 600 "$tar"
  ( cd "$dest" && sha256sum "$stamp.tar.gz" >"$stamp.tar.gz.sha256" ) || return 1
  chmod 600 "$dest/$stamp.tar.gz.sha256"
  printf '%s\n' "$stamp.tar.gz" >"$dest/LATEST"
  chmod 600 "$dest/LATEST"
  state_prune "$dest"
  say "personal-state snapshot: $tar"
}

# Prints the archive path and returns 0. Return 1 if there is no snapshot yet.
# Return 2 if the latest file is there but its checksum does not match: the caller
# must stop, not start an empty app over a snapshot it failed to read.
# Do not call `exit` from here. Callers read the path with a command substitution,
# and exit inside one only leaves that substitution.
state_latest_tar() {
  local name
  [ -r "$STATE_DEST/LATEST" ] || return 1
  name=$(tr -d '[:space:]' <"$STATE_DEST/LATEST")
  [ -n "$name" ] && [ -f "$STATE_DEST/$name" ] || return 1
  [ -f "$STATE_DEST/$name.sha256" ] || return 2
  if ! ( cd "$STATE_DEST" && sha256sum -c "$name.sha256" >/dev/null ); then
    return 2
  fi
  printf '%s\n' "$STATE_DEST/$name"
}

chown_ns() {
  local spec=$1 path=$2
  [ "${STATE_SKIP_CHOWN:-0}" = 1 ] && return 0
  [ -n "$spec" ] && [ -e "$path" ] || return 0
  command -v podman >/dev/null 2>&1 || return 0
  podman unshare chown "$spec" "$path" || warn "couldn't chown $path to $spec"
}

state_apply_secrets() {
  local f=$1 line name value
  [ -f "$f" ] || return 0
  if ! command -v podman >/dev/null 2>&1; then
    warn "podman isn't here; secrets in the snapshot were not loaded"
    return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      ''|\#*) continue ;;
    esac
    name=${line%%=*}
    value=${line#*=}
    if podman secret exists "$name" 2>/dev/null; then
      continue
    fi
    printf %s "$value" | podman secret create "$name" - >/dev/null
    say "restored podman secret $name (it was missing; an existing secret is never replaced)"
  done <"$f"
}

restore_from() {
  local archive=$1 tmp owner rel src dest
  tmp=$(mktemp -d)
  if ! tar -C "$tmp" -xzf "$archive"; then
    rm -rf "$tmp"
    die "couldn't read $archive"
  fi
  local app use_owner pg_owner
  app=$(sed -n 's/^app: //p' "$tmp/MANIFEST")
  [ "$app" = "$STATE_NAME" ] || { rm -rf "$tmp"; die "snapshot $archive is for ${app:-?}, not $STATE_NAME"; }
  owner=$(sed -n 's/^owner: //p' "$tmp/MANIFEST")
  pg_owner=$(sed -n 's/^pg_owner: //p' "$tmp/MANIFEST")
  mkdir -p "$STATE_TAR_ROOT"
  if [ -d "$tmp/payload" ]; then
    while IFS= read -r -d '' src; do
      rel=${src#"$tmp/payload"/}
      dest=$STATE_TAR_ROOT/$rel
      use_owner=$owner
      case $rel in
        postgres|postgres/*) [ -n "$pg_owner" ] && use_owner=$pg_owner ;;
      esac
      if [ -d "$src" ]; then
        mkdir -p "$dest"
        chown_ns "$use_owner" "$dest"
      else
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        chown_ns "$use_owner" "$dest"
      fi
    done < <(find "$tmp/payload" -mindepth 1 -print0)
  fi
  # The app user has to be able to create the WAL next to a restored database.
  # Chown that directory's inode only. Paperless's directory also holds media that
  # this snapshot does not own, so leave its inode alone.
  if [ "$STATE_TAR_ROOT" = "$STATE_DATA" ]; then
    chown_ns "$owner" "$STATE_DATA"
  fi
  if [ -f "$tmp/import/secrets.env" ]; then
    mkdir -p "$STATE_DATA/.cobra-restore"
    cp -a "$tmp/import/secrets.env" "$STATE_DATA/.cobra-restore/secrets.env"
    chmod 600 "$STATE_DATA/.cobra-restore/secrets.env"
    state_apply_secrets "$STATE_DATA/.cobra-restore/secrets.env"
  fi
  if [ -f "$tmp/import/dump.sql" ]; then
    mkdir -p "$STATE_DATA/.cobra-restore"
    cp -a "$tmp/import/dump.sql" "$STATE_DATA/.cobra-restore/dump.sql"
    chmod 600 "$STATE_DATA/.cobra-restore/dump.sql"
    say "database dump is staged. The app script imports it after MariaDB or Postgres initialises."
  elif [ -d "$STATE_DATA/.cobra-restore" ]; then
    rm -rf "$STATE_DATA/.cobra-restore"
  fi
  rm -rf "$tmp"
}

restore_state_if_empty() {
  local name=$1 status archive oldmask
  state_load "$name"
  if [ "${SKIP_STATE_RESTORE:-0}" = 1 ]; then
    say "SKIP_STATE_RESTORE=1: not restoring $name"
    return 0
  fi
  if state_present; then
    return 0
  fi
  status=$(state_root_status "$STATE_HOST")
  case $status in
    unmounted)
      die "$(state_root_hint unmounted) Not starting $name blank. Mount the vault, or SKIP_STATE_RESTORE=1 to start empty on purpose."
      ;;
    unset)
      return 0
      ;;
    ready) ;;
    *) die "can't tell where personal-state snapshots for $name would be" ;;
  esac
  state_prepare_dest || die "${STATE_DEST_ERR:-no personal-state directory for $name}"
  local latest_rc=0
  archive=$(state_latest_tar) || latest_rc=$?
  if [ "$latest_rc" = 2 ]; then
    die "latest personal-state snapshot for $name in $STATE_DEST failed its checksum. Not starting $name blank."
  fi
  if [ "$latest_rc" != 0 ]; then
    return 0
  fi
  say "restoring $name personal state from $archive"
  oldmask=$(umask)
  umask 077
  restore_from "$archive" || { umask "$oldmask"; return 1; }
  umask "$oldmask"
}

# Snapshot if the database is there. Never deletes the app's own files.
backup_state() {
  local name=$1 status oldmask stage
  state_load "$name"
  if ! state_present; then
    return 0
  fi
  status=$(state_root_status "$STATE_HOST")
  case $status in
    ready) ;;
    unmounted|unset)
      warn "personal-state backup of $name skipped: $(state_root_hint "$status")"
      return 1
      ;;
    *)
      warn "personal-state backup of $name skipped"
      return 1
      ;;
  esac
  state_prepare_dest || return 1
  STATE_OWNER=$(state_owner)
  STATE_PG_OWNER=
  stage=$(mktemp -d)
  STAGE=$stage
  mkdir -p "$STAGE/payload" "$STAGE/import"
  oldmask=$(umask)
  umask 077
  if ! fill_state; then
    umask "$oldmask"
    rm -rf "$stage"
    warn "personal-state backup of $name failed"
    return 1
  fi
  if ! state_pack "$STATE_DEST"; then
    umask "$oldmask"
    rm -rf "$stage"
    warn "personal-state backup of $name failed while packing"
    return 1
  fi
  umask "$oldmask"
  rm -rf "$stage"
}

snapshot_personal_state() {
  # A failed snapshot must not stop the app from starting, and must not delete its files.
  backup_state "$1" || true
  return 0
}

# Call after the data directories exist and before the container is replaced.
keep_personal_state() {
  snapshot_personal_state "$1"
  restore_state_if_empty "$1"
}

state_backup_host() {
  local host=$1 name failed=0 status root
  status=$(state_root_status "$host")
  case $status in
    ready) ;;
    *) die "$(state_root_hint "$status")" ;;
  esac
  root=$(state_root_path "$host")
  mkdir -p "$root" 2>/dev/null || die "can't create $root as $(id -un). As eels: sudo mkdir -p $root && sudo chown $(id -un): $root"
  chmod 700 "$root" 2>/dev/null || true
  while IFS= read -r name; do
    backup_state "$name" || failed=1
  done < <(state_app_names "$host")
  return "$failed"
}

state_install_timer() {
  local script=$1 unit_dir
  [ "${STATE_NO_TIMER:-0}" = 1 ] && return 0
  unit_dir=${HOME}/.config/systemd/user
  mkdir -p "$unit_dir"
  cat >"$unit_dir/cobra-state-backup.service" <<EOF
[Unit]
Description=Snapshot Cobra personal state (favorites, progress, per-user settings)

[Service]
Type=oneshot
ExecStart=$script
Environment=STATE_NO_TIMER=1
EOF
  cat >"$unit_dir/cobra-state-backup.timer" <<EOF
[Unit]
Description=Daily Cobra personal-state snapshot

[Timer]
OnCalendar=*-*-* 03:10:00
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
EOF
  if systemctl --user daemon-reload && systemctl --user enable --now cobra-state-backup.timer; then
    say "daily personal-state timer enabled (03:10, as $(id -un))"
  else
    warn "couldn't enable the daily timer. From a podsvc login: systemctl --user enable --now cobra-state-backup.timer"
  fi
}

state_force_aside() {
  local ts aside
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  case $STATE_NAME in
    paperless)
      if command -v podman >/dev/null 2>&1; then
        podman stop paperless postgres redis >/dev/null 2>&1 || true
      fi
      aside=$STATE_BASE/paperless.pre-restore-$ts
      [ -d "$STATE_DATA" ] && mv "$STATE_DATA" "$aside"
      [ -d "$STATE_BASE/postgres" ] && mv "$STATE_BASE/postgres" "$STATE_BASE/postgres.pre-restore-$ts"
      mkdir -p "$STATE_DATA"
      say "moved the current Paperless data aside ($aside and postgres.pre-restore-$ts). Nothing was deleted."
      ;;
    romm)
      if command -v podman >/dev/null 2>&1; then
        podman stop romm romm-db >/dev/null 2>&1 || true
      fi
      aside=$STATE_DATA.pre-restore-$ts
      [ -d "$STATE_DATA" ] && mv "$STATE_DATA" "$aside"
      mkdir -p "$STATE_DATA"
      say "moved the current RomM data aside ($aside). Nothing was deleted."
      ;;
    *)
      if command -v podman >/dev/null 2>&1; then
        podman stop "$STATE_CONTAINER" >/dev/null 2>&1 || true
      fi
      aside=$STATE_DATA.pre-restore-$ts
      if [ -d "$STATE_DATA" ]; then
        mv "$STATE_DATA" "$aside"
        say "moved the current $STATE_NAME data aside ($aside). Nothing was deleted."
      fi
      mkdir -p "$STATE_DATA"
      ;;
  esac
}

state_restore_cli() {
  local host=$1 name
  shift
  if [ $# -eq 0 ]; then
    while IFS= read -r name; do
      state_load "$name"
      if state_present; then
        continue
      fi
      restore_state_if_empty "$name" || return 1
    done < <(state_app_names "$host")
    return 0
  fi
  for name in "$@"; do
    state_load "$name"
    [ "$STATE_HOST" = "$host" ] || die "$name is a $STATE_HOST app. Run the $STATE_HOST state-restore.sh."
    if state_present && [ "${FORCE_STATE_RESTORE:-0}" != 1 ]; then
      die "$name already has personal state. Refusing to overwrite it. FORCE_STATE_RESTORE=1 $0 $name moves the current directory aside and restores the snapshot."
    fi
    if [ "${FORCE_STATE_RESTORE:-0}" = 1 ]; then
      state_force_aside
    fi
    restore_state_if_empty "$name" || return 1
    case $STATE_NAME in
      romm|paperless)
        say "then start it so the database import runs: ./$STATE_NAME.sh"
        ;;
      cobra-breaks)
        say "files are back in $STATE_DATA. Start the Quadlet (there is no podman script for this one)."
        ;;
      *)
        say "files are back. Start it with ./$STATE_CONTAINER.sh"
        ;;
    esac
  done
}

romm_table_count() {
  podman exec -i romm-db sh -c 'exec mariadb -N -u romm -p"$MARIADB_PASSWORD"' <<'SQL'
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'romm';
SQL
}

paperless_table_count() {
  podman exec -i postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -U paperless -d paperless -At' <<'SQL'
SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SQL
}

state_import_staged() {
  local name=$1 dump count
  state_load "$name"
  dump=$STATE_DATA/.cobra-restore/dump.sql
  [ -f "$dump" ] || return 0
  case $STATE_NAME in
    romm)
      count=$(romm_table_count | tr -d '[:space:]')
      if [ "${count:-0}" != 0 ]; then
        die "RomM already has ${count} tables and a staged dump at $dump, so the import did not finish cleanly. Move the broken data aside and rerun ./romm.sh (the snapshot is still on the vault): rm -rf $STATE_DATA/db $STATE_DATA/.cobra-restore"
      fi
      say "importing RomM database"
      if ! podman exec -i romm-db sh -c 'exec mariadb -u romm -p"$MARIADB_PASSWORD" romm' <"$dump"; then
        die "RomM import failed. Move the data dir aside and rerun ./romm.sh so MariaDB initialises empty and imports again: rm -rf $STATE_DATA/db $STATE_DATA/.cobra-restore"
      fi
      ;;
    paperless)
      count=$(paperless_table_count | tr -d '[:space:]')
      if [ "${count:-0}" != 0 ]; then
        die "Paperless already has ${count} tables and a staged dump at $dump. Move Postgres aside and rerun ./paperless.sh: rm -rf $STATE_BASE/postgres $STATE_DATA/.cobra-restore"
      fi
      say "importing Paperless database"
      if ! podman exec -i postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 -U paperless -d paperless' <"$dump"; then
        die "Paperless import failed. Move Postgres aside and rerun ./paperless.sh: rm -rf $STATE_BASE/postgres $STATE_DATA/.cobra-restore"
      fi
      ;;
    *) die "no database import for $STATE_NAME" ;;
  esac
  rm -rf "$STATE_DATA/.cobra-restore"
  say "$STATE_NAME database imported"
}
