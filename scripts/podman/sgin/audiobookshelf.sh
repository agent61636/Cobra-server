#!/usr/bin/env bash
# Audiobookshelf for audiobooks, ebooks, stand-up comedy and The Ward (recorded podcasts). http://10.6.9.20:13378
# Public: books.songofeo.com; comedy.songofeo.com and sessions.songofeo.com are the same server (docs/music.md)
# Run as podsvc on the SGIN:  ./audiobookshelf.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${ABS_IMAGE:-ghcr.io/advplyr/audiobookshelf:latest}
DATA=$STREAM_DATA/abs

preflight
need_folders "$BOOKS_DIR" "$AUDIOBOOKS_DIR" "$COMEDY_DIR" "$SESSIONS_DIR"
stream_pod
ensure_dir "$DATA/config" "$DATA/metadata"
keep_personal_state audiobookshelf

# PORT=13378: inside a pod every app shares one network, so ABS can't keep its default port 80.
run_container audiobookshelf "$STREAM_POD" "$IMAGE" \
  -e PORT=13378 \
  -v "$DATA/config:/config:Z" \
  -v "$DATA/metadata:/metadata:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port 13378 60 || warn "Audiobookshelf isn't answering on :13378 yet; check podman logs audiobookshelf"
snapshot_personal_state audiobookshelf
done_msg audiobookshelf http://10.6.9.20:13378
echo "    Once: first visit creates the admin, then Libraries -> add 'Audiobooks' (/media/$AUDIOBOOKS_DIR) and 'Books' (/media/$BOOKS_DIR, type Books),"
echo "          'Comedy' (/media/$COMEDY_DIR, type Book) and 'Sessions' (/media/$SESSIONS_DIR, type Podcast)"
