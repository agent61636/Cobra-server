#!/usr/bin/env bash
# RomM web arcade with EmulatorJS built in (games run in the player's browser), plus its MariaDB.
# http://10.6.9.20:8080  (public: arcade.songofeo.com). The hiscore board runs on the gate: ../gate/hiscore.sh
# Run as podsvc on the SGIN:  ./romm.sh
#
# Coming from the manual's Quadlet setup with a database already made? Give the old password once:
#   ROMM_DB_PASSWORD=<old DBPW> ROMM_AUTH_SECRET=<old SECRET> ./romm.sh
# Metadata keys (covers, names): put them in ~/.config/cobra/romm.env, e.g.
#   IGDB_CLIENT_ID=...  IGDB_CLIENT_SECRET=...  SCREENSCRAPER_USER=...  SCREENSCRAPER_PASSWORD=...  STEAMGRIDDB_API_KEY=...
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${ROMM_IMAGE:-docker.io/rommapp/romm:latest}
DB_IMAGE=${ROMM_DB_IMAGE:-docker.io/library/mariadb:11}
DATA=$STREAM_DATA/romm

preflight
need_pool roms
stream_pod
ensure_dir "$DATA/resources" "$DATA/assets" "$DATA/config" "$DATA/redis" "$DATA/db"

# Passwords live in podman secrets, not in the script or in `podman inspect`.
ensure_secret romm-db-password "${ROMM_DB_PASSWORD:-}"
ensure_secret romm-db-root-password "${ROMM_DB_PASSWORD:-}"
ensure_secret romm-auth-secret "${ROMM_AUTH_SECRET:-$(random_hex 32)}"

# Netplay in the browser (part 3.8b). Written once; edit it freely afterwards.
if [ ! -e "$DATA/config/config.yml" ]; then
  cat >"$DATA/config/config.yml" <<'YML'
emulatorjs:
  netplay:
    enabled: true
YML
  say "wrote $DATA/config/config.yml (EmulatorJS netplay on)"
fi

run_container romm-db "$STREAM_POD" "$DB_IMAGE" \
  -e MARIADB_DATABASE=romm -e MARIADB_USER=romm \
  --secret romm-db-password,type=env,target=MARIADB_PASSWORD \
  --secret romm-db-root-password,type=env,target=MARIADB_ROOT_PASSWORD \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 10s \
  -v "$DATA/db:/var/lib/mysql:Z"

say "waiting for MariaDB"
for _ in $(seq 60); do
  [ "$(podman inspect -f '{{.State.Health.Status}}' romm-db 2>/dev/null)" = healthy ] && break
  podman healthcheck run romm-db >/dev/null 2>&1 || true
  sleep 2
done
[ "$(podman inspect -f '{{.State.Health.Status}}' romm-db)" = healthy ] || warn "MariaDB isn't healthy yet; RomM keeps retrying (podman logs romm-db)"

# keep-groups: RomM writes into the shared roms folder (group media).
# The roms mount has no :Z because the cabinet reads the same folder over Samba.
run_container romm "$STREAM_POD" "$IMAGE" \
  --group-add keep-groups \
  -e DB_HOST=127.0.0.1 -e DB_NAME=romm -e DB_USER=romm \
  --secret romm-db-password,type=env,target=DB_PASSWD \
  --secret romm-auth-secret,type=env,target=ROMM_AUTH_SECRET_KEY \
  -v "$DATA/resources:/romm/resources:Z" \
  -v "$DATA/assets:/romm/assets:Z" \
  -v "$DATA/config:/romm/config:Z" \
  -v "$DATA/redis:/redis-data:Z" \
  -v "$POOL/roms:/romm/library/roms"

wait_port 8080 120 || warn "RomM isn't answering on :8080 yet; check podman logs romm"
done_msg romm http://10.6.9.20:8080
cat <<'TXT'
    Once (part 3.8b): first visit runs the setup wizard (admin user), then Scan.
      ROMs go in \\cobra-stream\roms\<platform>\  (e.g. snes, n64, arcade)
      BIOS: the platform -> Firmware -> upload.  One RomM user per player, so saves stay separate.
TXT
