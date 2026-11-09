#!/usr/bin/env bash
# Uptime Kuma: watches every app and alerts you when one goes down. https://status.songofeo.com (behind Authelia)
# Run as podsvc on the gate:  ./uptime-kuma.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${KUMA_IMAGE:-docker.io/louislam/uptime-kuma:2}
DATA=$GATE_DATA/uptime-kuma

preflight
gate_pod
ensure_dir "$DATA"
keep_personal_state uptime-kuma

run_container uptime-kuma "$GATE_POD" "$IMAGE" \
  -v "$DATA:/app/data:Z"

pod_http uptime-kuma http://127.0.0.1:3001 90 || warn "Uptime Kuma isn't answering yet; check podman logs uptime-kuma"
snapshot_personal_state uptime-kuma
done_msg uptime-kuma https://status.songofeo.com
echo "    Monitors to add: part 5.7"
