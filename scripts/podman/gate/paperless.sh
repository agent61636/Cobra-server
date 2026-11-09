#!/usr/bin/env bash
# Paperless-ngx document archive with its Postgres and Redis. https://papers.songofeo.com (behind Authelia)
# Inbox: drop files in \\cobra-stream\scans; Paperless files them within a minute.
# Run as podsvc on the gate:  ./paperless.sh
#
# Coming from the manual's Quadlet setup? Give the old values once, so the existing database still opens:
#   PAPERLESS_DB_PASSWORD=<old PGPW> PAPERLESS_SECRET=<old PLKEY> ./paperless.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${PAPERLESS_IMAGE:-ghcr.io/paperless-ngx/paperless-ngx:latest}
PG_IMAGE=${PAPERLESS_PG_IMAGE:-docker.io/library/postgres:16}
REDIS_IMAGE=${PAPERLESS_REDIS_IMAGE:-docker.io/library/redis:7}
DATA=$GATE_DATA/paperless

preflight
need_folders "$SCANS_DIR"
gate_pod
ensure_dir "$DATA/data" "$DATA/media" "$DATA/export" "$GATE_DATA/postgres" "$GATE_DATA/redis"
keep_personal_state paperless

ensure_secret paperless-db-password "${PAPERLESS_DB_PASSWORD:-}"
ensure_secret paperless-secret-key "${PAPERLESS_SECRET:-$(random_hex 32)}"

run_container postgres "$GATE_POD" "$PG_IMAGE" \
  -e POSTGRES_DB=paperless -e POSTGRES_USER=paperless \
  --secret paperless-db-password,type=env,target=POSTGRES_PASSWORD \
  -v "$GATE_DATA/postgres:/var/lib/postgresql/data:Z"

run_container redis "$GATE_POD" "$REDIS_IMAGE" \
  -v "$GATE_DATA/redis:/data:Z"

say "waiting for Postgres"
for _ in $(seq 60); do
  podman exec postgres pg_isready -q -U paperless 2>/dev/null && break
  sleep 2
done
podman exec postgres pg_isready -q -U paperless || warn "Postgres isn't ready yet; Paperless retries on its own (podman logs postgres)"
state_import_staged paperless

# The scans folder comes over the CIFS mount from the SGIN (no :Z on a network share).
# Polling: change notifications don't cross SMB.
run_container paperless "$GATE_POD" "$IMAGE" \
  -e PAPERLESS_DBHOST=127.0.0.1 \
  -e PAPERLESS_REDIS=redis://127.0.0.1:6379 \
  -e PAPERLESS_URL=https://papers.songofeo.com \
  -e PAPERLESS_CONSUMER_POLLING=60 \
  -e PAPERLESS_TIME_ZONE="$COBRA_TZ" \
  --secret paperless-db-password,type=env,target=PAPERLESS_DBPASS \
  --secret paperless-secret-key,type=env,target=PAPERLESS_SECRET_KEY \
  -v "$DATA/data:/usr/src/paperless/data:Z" \
  -v "$DATA/media:/usr/src/paperless/media:Z" \
  -v "$DATA/export:/usr/src/paperless/export:Z" \
  -v "$DISKS/$SCANS_DIR:/usr/src/paperless/consume"

pod_http paperless http://127.0.0.1:8000 180 || warn "Paperless isn't answering yet (first start migrates the database; give it a few minutes)"
snapshot_personal_state paperless
done_msg paperless https://papers.songofeo.com
echo "    Once: podman exec -it paperless python3 manage.py createsuperuser"
