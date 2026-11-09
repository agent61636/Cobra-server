#!/usr/bin/env bash
# The hiscore board from part 7 (apps/hiscore in this repo): cabinet and browser high scores at scores.songofeo.com.
# Runs on the stock Python image straight from /srv/gate/hiscore-app; there's nothing to build.
# Run as podsvc on the gate:  ./hiscore.sh
# If this repo is checked out on the gate, the script installs or refreshes the app from apps/hiscore/ itself.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${HISCORE_IMAGE:-docker.io/library/python:3.13-slim}
APP=$GATE_DATA/hiscore-app
DATA=$GATE_DATA/hiscore
REPO_APP=$here/../../../apps/hiscore/hiscore

preflight
gate_pod
ensure_dir "$APP" "$DATA"
keep_personal_state hiscore

if [ -d "$REPO_APP" ]; then
  rm -rf "$APP/hiscore" && cp -r "$REPO_APP" "$APP/hiscore"
  say "installed the app from $(cd "$REPO_APP" && pwd)"
fi
[ -r "$APP/hiscore/__main__.py" ] || die "no app in $APP/hiscore. Copy apps/hiscore/hiscore there (part 7.1), or run this from a checkout of the repo"
[ -s "$DATA/keys.txt" ] || warn "no $DATA/keys.txt: the cabinet can't upload until you add its key (part 7.2)"

run_container hiscore "$GATE_POD" "$IMAGE" \
  -e HISCORE_DATA=/data -e HISCORE_BIND=127.0.0.1:8090 -e PYTHONDONTWRITEBYTECODE=1 \
  -v "$APP:/app:ro,Z" \
  -v "$DATA:/data:Z" \
  -w /app \
  -- python -m hiscore

ok=
for _ in $(seq 20); do
  if podman exec hiscore python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz')" 2>/dev/null; then ok=1; break; fi
  sleep 1
done
[ -n "$ok" ] || warn "hiscore isn't answering on /healthz yet; check podman logs hiscore"
snapshot_personal_state hiscore
done_msg hiscore https://scores.songofeo.com
echo "    New cabinet key: cd $APP && podman run --rm -v \"\$PWD\":/app:ro,Z -w /app $IMAGE python -m hiscore hash-key cabinet"
