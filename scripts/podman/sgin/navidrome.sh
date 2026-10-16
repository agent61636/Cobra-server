#!/usr/bin/env bash
# Navidrome music server, one music library per person. http://10.6.9.20:4533
# (public: music.songofeo.com, eelsmusic.songofeo.com and rupaulradio.songofeo.com, all the same server)
# Trusts the gate's Remote-User header (the station's Authelia sign-in, part 5.4), so Music doesn't ask twice.
# Run as podsvc on the SGIN:  ./navidrome.sh            other people:  MUSIC_USERS="eels rachel sam" ./navidrome.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${NAVIDROME_IMAGE:-docker.io/deluan/navidrome:latest}
DATA=$STREAM_DATA/navidrome
# Each name gets its own folder, music/<name>, on the pool. The first one is the default library.
read -r -a USERS <<<"${MUSIC_USERS:-eels rachel}"
[ "${#USERS[@]}" -ge 1 ] || die "MUSIC_USERS is empty"

preflight
folders=()
for u in "${USERS[@]}"; do folders+=("music/$u"); done
need_pool "${folders[@]}"
stream_pod
ensure_dir "$DATA"

run_container navidrome "$STREAM_POD" "$IMAGE" \
  -e ND_MUSICFOLDER="/media/music/${USERS[0]}" \
  -e ND_SESSIONTIMEOUT=8h \
  -e ND_ENABLEINSIGHTSCOLLECTOR=false \
  -e ND_REVERSEPROXYWHITELIST=10.6.9.10/32 \
  -v "$DATA:/data:Z" \
  -v "$POOL:/media:ro"

wait_port 4533 60 || warn "Navidrome isn't answering on :4533 yet; check podman logs navidrome"
done_msg navidrome http://10.6.9.20:4533
echo "    Once (part 3.8): first visit creates the admin. Then Settings -> Libraries -> add one library per person:"
for u in "${USERS[@]:1}"; do echo "      /media/music/$u"; done
echo "    Settings -> Users -> one user each, with access to only their own library:"
for u in "${USERS[@]}"; do echo "      $u -> /media/music/$u"; done
