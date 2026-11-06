#!/usr/bin/env bash
# Navidrome music servers: one separate instance per person (and one for stand-up comedy), never one
# instance with several libraries. Run as podsvc on the SGIN.
#
#   ./navidrome.sh                Eels':     navidrome         :4533  all of music/    music.songofeo.com
#   ./navidrome.sh rachel         Rachel's:  navidrome-rachel  :4535  music/rachel     mustang.songofeo.com
#   ./navidrome.sh comedy         Comedy:    navidrome-comedy  :4534  comedy/          comedy.songofeo.com
#   ./navidrome.sh sessions       Podcasts:  navidrome-sessions :4536 sessions/       sessions.songofeo.com
#   ./navidrome.sh sam 4537       someone new: music/sam on :4537 (add the port to STREAM_PORTS in pod.sh,
#                                 RECREATE_POD=1 ./up-all.sh, the nftables line (part 3.7) and a name on the gate)
#
# Each one trusts the gate's Remote-User header (the station's Authelia sign-in, part 5.4), so it doesn't ask twice.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${NAVIDROME_IMAGE:-docker.io/deluan/navidrome:latest}
who=${1:-}
case $who in
  "")     NAME=navidrome;         PORT=4533;        FOLDER=$MUSIC_DIR ;;
  comedy) NAME=navidrome-comedy;  PORT=4534;        FOLDER=$COMEDY_DIR ;;
  rachel) NAME=navidrome-rachel;  PORT=4535;        FOLDER=$MUSIC_DIR/rachel ;;
  sessions) NAME=navidrome-sessions; PORT=4536;      FOLDER=$SESSIONS_DIR ;;
  *)      NAME=navidrome-$who;    PORT=${2:-};      FOLDER=$MUSIC_DIR/$who
          [ -n "$PORT" ] || die "give $who a port: ./navidrome.sh $who 4537" ;;
esac
DATA=$STREAM_DATA/$NAME

preflight
need_folders "$FOLDER"
stream_pod
ensure_dir "$DATA"

run_container "$NAME" "$STREAM_POD" "$IMAGE" \
  -e ND_PORT="$PORT" \
  -e ND_MUSICFOLDER="/media/$FOLDER" \
  -e ND_SESSIONTIMEOUT=8h \
  -e ND_ENABLEINSIGHTSCOLLECTOR=false \
  -e ND_REVERSEPROXYWHITELIST=10.6.9.10/32 \
  -v "$DATA:/data:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port "$PORT" 60 || warn "$NAME isn't answering on :$PORT yet; check podman logs $NAME (is :$PORT in STREAM_PORTS in pod.sh?)"
done_msg "$NAME" "http://10.6.9.20:$PORT"
echo "    Once: the first visit creates its admin. Use the same username as in the gate's Authelia users.yml."
