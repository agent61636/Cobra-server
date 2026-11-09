#!/usr/bin/env bash
# Kavita for comics, manga and graphic novels. http://10.6.9.20:5000  (public: comics.songofeo.com)
# Run as podsvc on the SGIN:  ./kavita.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${KAVITA_IMAGE:-docker.io/jvmilazz0/kavita:latest}
DATA=$STREAM_DATA/kavita

preflight
need_folders "$COMICS_DIR"
stream_pod
ensure_dir "$DATA"
keep_personal_state kavita

run_container kavita "$STREAM_POD" "$IMAGE" \
  -v "$DATA:/kavita/config:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port 5000 60 || warn "Kavita isn't answering on :5000 yet; check podman logs kavita"
snapshot_personal_state kavita
done_msg kavita http://10.6.9.20:5000
echo "    Once: first visit creates the admin, then Libraries -> add 'Comics' (type Comic) with folder /media/$COMICS_DIR"
