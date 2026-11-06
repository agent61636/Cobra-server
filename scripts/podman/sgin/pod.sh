# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this
# The SGIN's "stream" pod (cobra-stream, 10.6.9.20). Sourced by the scripts in this folder.
# Every app in the pod reaches the others on 127.0.0.1; the LAN reaches only these published ports,
# and nftables (part 3.7) limits them to the LAN and WireGuard.
#
#   8096 Jellyfin   8409 ErsatzTV   13378 Audiobookshelf   5000 Kavita
#   4533 Navidrome (Eels)  4534 Navidrome (comedy)  4535 Navidrome (Rachel)  4536 Navidrome (sessions)
#   4537-4549 Cobra N.A.V. clone slots (scripts/nav)
#   8080 RomM       8000  Icecast (radio, part 8)
STREAM_POD=stream
STREAM_PORTS=(8096:8096 8409:8409 13378:13378 5000:5000 4533:4533 4534:4534 4535:4535 4536:4536 4537-4549:4537-4549 8080:8080 8000:8000)
STREAM_DATA=${COBRA_DATA:-/srv/stream}

stream_pod() { ensure_pod "$STREAM_POD" "${STREAM_PORTS[@]}"; }

# The Intel GPU (Quick Sync) for Jellyfin and ErsatzTV.
need_gpu() {
  [ -e /dev/dri/renderD128 ] || die "/dev/dri/renderD128 is missing: the Intel driver isn't loaded (part 3.3)"
  id -nG | tr ' ' '\n' | grep -qx render \
    || die "$(id -un) isn't in the render group. As eels: sudo usermod -aG render,video $(id -un), then log in again"
}
