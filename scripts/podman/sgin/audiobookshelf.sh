#!/usr/bin/env bash
# Audiobookshelf for audiobooks and ebooks. http://10.6.9.20:13378  (public: books.songofeo.com)
# Run as podsvc on the SGIN:  ./audiobookshelf.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${ABS_IMAGE:-ghcr.io/advplyr/audiobookshelf:latest}
DATA=$STREAM_DATA/abs

preflight
need_folders "$BOOKS_DIR" "$AUDIOBOOKS_DIR"
stream_pod
ensure_dir "$DATA/config" "$DATA/metadata"

# PORT=13378: inside a pod every app shares one network, so ABS can't keep its default port 80.
run_container audiobookshelf "$STREAM_POD" "$IMAGE" \
  -e PORT=13378 \
  -v "$DATA/config:/config:Z" \
  -v "$DATA/metadata:/metadata:Z" \
  -v "$DISKS:/media:ro,rbind"

wait_port 13378 60 || warn "Audiobookshelf isn't answering on :13378 yet; check podman logs audiobookshelf"
done_msg audiobookshelf http://10.6.9.20:13378
echo "    Once: first visit creates the admin, then Libraries -> add 'Audiobooks' (/media/$AUDIOBOOKS_DIR) and 'Books' (/media/$BOOKS_DIR, type Books)"
