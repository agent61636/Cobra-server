#!/usr/bin/env bash
# Navidrome music server, one music library per person. http://10.6.9.20:4533
# (public: music.songofeo.com for Eels, who sees every library as admin, and mustang.songofeo.com for Rachel; the same server)
# Trusts the gate's Remote-User header (the station's Authelia sign-in, part 5.4), so Music doesn't ask twice.
# Run as podsvc on the SGIN:  ./navidrome.sh            other people:  MUSIC_USERS="eels rachel sam" ./navidrome.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${NAVIDROME_IMAGE:-docker.io/deluan/navidrome:latest}
DATA=$STREAM_DATA/navidrome
# Each name gets its own folder, music/<name>, on dock1a ($MUSIC_DIR in lib.sh). The first one is the default library.
read -r -a USERS <<<"${MUSIC_USERS:-eels rachel}"
[ "${#USERS[@]}" -ge 1 ] || die "MUSIC_USERS is empty"

preflight
folders=()
for u in "${USERS[@]}"; do folders+=("$MUSIC_DIR/$u"); done
need_folders "${folders[@]}"
stream_pod
ensure_dir "$DATA"

run_container navidrome "$STREAM_POD" "$IMAGE" \
  -e ND_MUSICFOLDER="/media/$MUSIC_DIR/${USERS[0]}" \
  -e ND_SESSIONTIMEOUT=8h \
  -e ND_ENABLEINSIGHTSCOLLECTOR=false \
  -e ND_REVERSEPROXYWHITELIST=10.6.9.10/32 \
  -v "$DATA:/data:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port 4533 60 || warn "Navidrome isn't answering on :4533 yet; check podman logs navidrome"
done_msg navidrome http://10.6.9.20:4533
echo "    Once (part 3.8): first visit creates the admin. Then Settings -> Libraries -> add one library per person:"
for u in "${USERS[@]:1}"; do echo "      /media/$MUSIC_DIR/$u"; done
echo "    Settings -> Users -> one user each, with access to only their own library:"
for u in "${USERS[@]}"; do echo "      $u -> /media/$MUSIC_DIR/$u"; done
