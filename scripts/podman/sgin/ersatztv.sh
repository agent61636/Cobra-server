#!/usr/bin/env bash
# ErsatzTV: live TV channels and a program guide built from your library (playlists, collections, filler).
# Jellyfin shows them under Live TV. http://10.6.9.20:8409 (LAN only)
# Run as podsvc on the SGIN:  ./ersatztv.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${ERSATZTV_IMAGE:-ghcr.io/ersatztv/legacy:latest}
DATA=$STREAM_DATA/ersatztv

preflight
need_gpu
need_folders "$FILLER_DIR"
stream_pod
ensure_dir "$DATA"
keep_personal_state ersatztv

# Same /media path as Jellyfin, so file paths Jellyfin reports open here too.
# /transcode in RAM: ErsatzTV writes each channel's live segments there while someone watches.
run_container ersatztv "$STREAM_POD" "$IMAGE" \
  --device /dev/dri \
  --group-add keep-groups \
  -v "$DATA:/config:Z" \
  -v "$DISKS:/media:ro,rbind" \
  --tmpfs /transcode:rw,size=2g,mode=1777

wait_port 8409 90 || warn "ErsatzTV isn't answering on :8409 yet; check podman logs ersatztv"
snapshot_personal_state ersatztv
done_msg ersatztv http://10.6.9.20:8409
cat <<'TXT'
    Set up channels (part 3.8a):
      1. Jellyfin -> Dashboard -> API Keys -> new key "ersatztv"
      2. ErsatzTV -> Media Sources -> Jellyfin: http://127.0.0.1:8096 + the key -> Sync Movies and TV
         ErsatzTV -> Media Sources -> Local: Other Videos, folder /media/wd1/filler -> Scan
      3. Settings -> FFmpeg Profiles: VAAPI, driver iHD, /dev/dri/renderD128, H.264, 1080p
      4. Lists -> Playlists (or Collections) -> Schedules -> Channels -> Playouts -> Build
      5. Jellyfin -> Dashboard -> Live TV:
           M3U tuner   http://127.0.0.1:8409/iptv/channels.m3u
           XMLTV guide http://127.0.0.1:8409/iptv/xmltv.xml   -> Refresh Guide Data
TXT
