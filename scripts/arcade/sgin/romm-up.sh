#!/usr/bin/env bash
# SGIN (cobra-stream), as podsvc:  sudo machinectl shell podsvc@   then   bash /tmp/cobra-arcade/romm-up.sh
# Starts RomM (web arcade, EmulatorJS) + its MariaDB in the stream pod on :8080.
# Quadlet SGIN (stream.pod in ~/.config/containers/systemd): writes romm-db.container + romm.container.
# Script SGIN (pod made by scripts/podman): runs scripts/podman/sgin/romm.sh.
# Never overwrites: existing romm Quadlets, secrets, config.yml and romm.env are kept as they are.
# Old database with a known password:  ROMM_DB_PASSWORD=<old> ROMM_AUTH_SECRET=<old> bash romm-up.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
Q=$HOME/.config/containers/systemd
CONF=$HOME/.config/cobra
DATA=${COBRA_DATA:-/srv/stream}/romm
DISKS=${COBRA_DISKS:-/srv/storage/disks}
ROMS=$DISKS/dock1b/roms
PLATFORMS=$DISKS/dock1a/backups/arcade/romm-platforms.yml
say() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -un)" = podsvc ] || die "run as podsvc: sudo machinectl shell podsvc@"
[ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] || die "no user session: use sudo machinectl shell podsvc@ (not sudo su)"
mountpoint -q "$DISKS/dock1b" || die "dock1b isn't mounted. As eels: bash /tmp/cobra-arcade/check.sh"
[ -d "$ROMS" ] && [ -w "$ROMS" ] || die "$ROMS is missing or not writable by podsvc. As eels: bash /tmp/cobra-arcade/check.sh"

if [ -f "$Q/stream.pod" ]; then MODE=quadlet
elif podman pod exists stream; then MODE=scripts
else die "no stream pod: neither $Q/stream.pod nor a pod named stream. Do part 3.8 first"; fi
say "stream pod is run by: $MODE"

if [ "$MODE" = scripts ]; then
  for s in "$here/podman/sgin/romm.sh" "$here/../../podman/sgin/romm.sh"; do
    [ -x "$s" ] && { say "running $s"; exec "$s"; }
    [ -f "$s" ] && { say "running $s"; exec bash "$s"; }
  done
  die "romm.sh not found next to this script (expected $here/podman/sgin/romm.sh)"
fi

grep -q '^PublishPort=8080:8080' "$Q/stream.pod" || die "$Q/stream.pod doesn't publish 8080. Add the line PublishPort=8080:8080 under [Pod], then: systemctl --user daemon-reload && systemctl --user restart stream-pod"

mkdir -p "$DATA"/{resources,assets,config,redis,db} "$CONF"
chmod 700 "$CONF"

have_db=0
[ -n "$(ls -A "$DATA/db" 2>/dev/null)" ] && have_db=1
if [ "$have_db" = 1 ] && ! podman secret exists romm-db-password && [ -z "${ROMM_DB_PASSWORD:-}" ]; then
  die "$DATA/db already holds a RomM database, and there's no saved password for it.
       Find the old one (password manager, or: grep -o 'DB_PASSWD=[^ ]*' ~/quadlet-old/romm.container), then:
       ROMM_DB_PASSWORD=<old> ROMM_AUTH_SECRET=<old secret> bash $0"
fi

rnd() { od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n'; }
mksecret() {
  podman secret exists "$1" && { say "secret $1 already exists, kept"; return; }
  printf %s "${2:-$(rnd 24)}" | podman secret create "$1" - >/dev/null
  say "created secret $1"
}
mksecret romm-db-password "${ROMM_DB_PASSWORD:-}"
mksecret romm-db-root-password "${ROMM_DB_PASSWORD:-}"
mksecret romm-auth-secret "${ROMM_AUTH_SECRET:-$(rnd 32)}"

[ -e "$CONF/romm.env" ] || { install -m 600 /dev/null "$CONF/romm.env"; say "made empty $CONF/romm.env (metadata keys go here)"; }

if [ ! -e "$DATA/config/config.yml" ]; then
  {
    printf 'emulatorjs:\n  netplay:\n    enabled: true\n'
    if [ -r "$PLATFORMS" ]; then printf 'system:\n'; sed 's/\r$//; s/^/  /' "$PLATFORMS"; fi
  } >"$DATA/config/config.yml"
  say "wrote $DATA/config/config.yml$([ -r "$PLATFORMS" ] && echo " with the cabinet's folder map")"
else
  say "kept existing $DATA/config/config.yml"
  if [ -r "$PLATFORMS" ] && ! grep -q '^ *platforms:' "$DATA/config/config.yml"; then
    warn "the cabinet's folder map ($PLATFORMS) isn't in config.yml yet. Add it with: bash $here/romm-platforms.sh"
  fi
fi

write_unit() {
  if [ -e "$Q/$1" ]; then say "kept existing $Q/$1"; cat >/dev/null; return; fi
  cat >"$Q/$1"; chmod 600 "$Q/$1"; say "wrote $Q/$1"
}

write_unit romm-db.container <<UNIT
[Unit]
Description=RomM database (MariaDB)
[Container]
ContainerName=romm-db
Image=docker.io/library/mariadb:11
Pod=stream.pod
AutoUpdate=registry
Timezone=local
Environment=MARIADB_DATABASE=romm MARIADB_USER=romm
Secret=romm-db-password,type=env,target=MARIADB_PASSWORD
Secret=romm-db-root-password,type=env,target=MARIADB_ROOT_PASSWORD
HealthCmd=healthcheck.sh --connect --innodb_initialized
HealthInterval=10s
HealthStartPeriod=60s
Notify=healthy
Volume=$DATA/db:/var/lib/mysql:Z
[Service]
TimeoutStartSec=300
[Install]
WantedBy=default.target
UNIT

write_unit romm.container <<UNIT
[Unit]
Description=RomM web arcade (EmulatorJS)
Requires=romm-db.service
After=romm-db.service
[Container]
ContainerName=romm
Image=docker.io/rommapp/romm:latest
Pod=stream.pod
AutoUpdate=registry
Timezone=local
GroupAdd=keep-groups
Environment=DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=romm DB_USER=romm
Secret=romm-db-password,type=env,target=DB_PASSWD
Secret=romm-auth-secret,type=env,target=ROMM_AUTH_SECRET_KEY
EnvironmentFile=$CONF/romm.env
Volume=$DATA/resources:/romm/resources:Z
Volume=$DATA/assets:/romm/assets:Z
Volume=$DATA/config:/romm/config:Z
Volume=$DATA/redis:/redis-data:Z
Volume=$ROMS:/romm/library/roms
[Service]
TimeoutStartSec=900
[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user is-active --quiet stream-pod || { say "starting stream-pod"; systemctl --user start stream-pod; }
say "starting romm-db (first run downloads MariaDB: a few quiet minutes)"
systemctl --user start romm-db.service || die "romm-db didn't start. Look at: journalctl --user -u romm-db -n 50"
say "starting romm (first run downloads RomM: a few quiet minutes)"
systemctl --user start romm.service || die "romm didn't start. Look at: journalctl --user -u romm -n 50"

say "waiting for RomM on :8080"
for _ in $(seq 120); do
  if curl -fsS -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
    podman ps --filter name=romm --format '  {{.Names}}  {{.Status}}'
    say "RomM is up: http://10.6.9.20:8080  (public: https://arcade.songofeo.com)"
    echo "    secrets: podman secret inspect --showsecret --format '{{.SecretData}}' romm-db-password"
    echo "    logs:    journalctl --user -u romm -f      restart: systemctl --user restart romm"
    exit 0
  fi
  sleep 3
done
die "RomM isn't answering on :8080 after 6 minutes. Look at: podman logs --tail 50 romm"
