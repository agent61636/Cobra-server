#!/usr/bin/env bash
# MeTube: paste a video link, it downloads with yt-dlp into the library's youtube folder.
# https://metube.songofeo.com (behind Authelia). Jellyfin can show the folder as /media/wd2/youtube.
# Run as podsvc on the gate:  ./metube.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${METUBE_IMAGE:-ghcr.io/alexta69/metube:latest}
DATA=$GATE_DATA/metube

preflight
need_folders "$YOUTUBE_DIR"
gate_pod
ensure_dir "$DATA"

# Finished videos go to the SGIN's wd2 (a folder on the Seagate); the queue and partial downloads stay on the gate's disk.
run_container metube "$GATE_POD" "$IMAGE" \
  -e DOWNLOAD_DIR=/downloads -e STATE_DIR=/state -e TEMP_DIR=/state/tmp \
  -v "$DISKS/$YOUTUBE_DIR:/downloads" \
  -v "$DATA:/state:Z"

pod_http metube http://127.0.0.1:8081 60 || warn "MeTube isn't answering yet; check podman logs metube"
done_msg metube https://metube.songofeo.com
echo "    yt-dlp ages fast: when downloads start failing, UPDATE=1 ./metube.sh"
