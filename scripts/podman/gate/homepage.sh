#!/usr/bin/env bash
# Homepage: the dashboard at home.songofeo.com, one tile per app with a live up/down dot.
# The first run copies the starter settings.yaml and services.yaml from ./homepage/ (part 5.7); later runs keep your edits.
# Run as podsvc on the gate:  ./homepage.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${HOMEPAGE_IMAGE:-ghcr.io/gethomepage/homepage:latest}
DATA=$GATE_DATA/homepage

preflight
gate_pod
ensure_dir "$DATA"
for f in settings.yaml services.yaml; do
  if [ ! -e "$DATA/$f" ]; then cp "$here/homepage/$f" "$DATA/$f"; say "wrote starter $DATA/$f"; fi
done

run_container homepage "$GATE_POD" "$IMAGE" \
  -e HOMEPAGE_ALLOWED_HOSTS=home.songofeo.com \
  -v "$DATA:/app/config:Z"

pod_http homepage http://127.0.0.1:3000 60 || warn "Homepage isn't answering yet; check podman logs homepage"
done_msg homepage https://home.songofeo.com
echo "    Edit $DATA/services.yaml to change tiles; Homepage picks up changes by itself."
