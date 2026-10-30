#!/usr/bin/env bash
# Jellyfin with Intel Quick Sync (QSV) hardware transcoding. http://10.6.9.20:8096  (public: tv.songofeo.com)
# Run as podsvc on the SGIN:  sudo machinectl shell podsvc@   then   ./jellyfin.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${JELLYFIN_IMAGE:-docker.io/jellyfin/jellyfin:latest}
DATA=$STREAM_DATA/jellyfin

preflight
need_gpu
need_folders "$MOVIES_DIR" "$SHOWS_DIR" "$MOVIES2_DIR" "$SHOWS2_DIR" "$FILLER_DIR" "$PREROLLS_DIR" "$YOUTUBE_DIR"
stream_pod
ensure_dir "$DATA/config" "$DATA/cache"

# --device /dev/dri + keep-groups: the container keeps podsvc's render group, so it may open the GPU.
# Config and cache stay on the SGIN's SSD; the library is read-only (no :Z, it's shared with Samba).
# --tmpfs /transcode-ram: optional RAM scratch for transcodes (Dashboard -> Playback -> Transcode path).
run_container jellyfin "$STREAM_POD" "$IMAGE" \
  --device /dev/dri \
  --group-add keep-groups \
  -e JELLYFIN_PublishedServerUrl=https://tv.songofeo.com \
  -v "$DATA/config:/config:Z" \
  -v "$DATA/cache:/cache:Z" \
  -v "$DISKS:/media:ro,rbind" \
  --tmpfs /transcode-ram:rw,size=4g,mode=1777

wait_port 8096 90 || warn "Jellyfin isn't answering on :8096 yet; check podman logs jellyfin"

# Can ffmpeg inside the container see the GPU? HEVC lines = QSV will work.
if podman exec jellyfin /usr/lib/jellyfin-ffmpeg/vainfo --display drm --device /dev/dri/renderD128 2>/dev/null | grep -qi hevc; then
  say "QSV check passed: the container sees the GPU's HEVC profiles"
else
  warn "QSV check failed: no HEVC profiles inside the container, so transcodes will fall back to the CPU. Check part 3.3: intel-media-va-driver-non-free, firmware-intel-graphics (HuC), enable_guc=2"
fi

done_msg jellyfin http://10.6.9.20:8096
cat <<'TXT'
    Once, in Jellyfin -> Dashboard -> Playback -> Transcoding (part 3.8):
      Hardware acceleration  Intel QuickSync (QSV), device /dev/dri/renderD128
      Hardware decoding      H264, HEVC, HEVC 10bit, VP9 (not AV1: Jasper Lake can't decode it)
      Hardware encoding on, Intel Low-Power H.264 and HEVC encoders on, tone mapping on (VPP too)
    Dashboard -> Networking -> Known proxies: 10.6.9.10 (the gate)
TXT
