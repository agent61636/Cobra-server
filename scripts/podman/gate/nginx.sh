#!/usr/bin/env bash
# nginx: the front door for every *.songofeo.com app (TLS with the wildcard cert, Authelia in front).
# Needs the site config from part 5.4 in /srv/gate/nginx/conf.d and the cert from part 5.3 in /srv/gate/nginx/certs.
# Run as podsvc on the gate:  sudo machinectl shell podsvc@   then   ./nginx.sh
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

IMAGE=${NGINX_IMAGE:-docker.io/library/nginx:stable}
DATA=$GATE_DATA/nginx

preflight
gate_pod
ensure_dir "$DATA/conf.d" "$DATA/certs"
[ -r "$DATA/certs/fullchain.pem" ] || warn "no $DATA/certs/fullchain.pem yet: run the certificate step (part 5.3) or nginx won't start"
ls "$DATA"/conf.d/*.conf >/dev/null 2>&1 || warn "no site config in $DATA/conf.d yet (part 5.4)"

run_container nginx "$GATE_POD" "$IMAGE" \
  -v "$DATA/conf.d:/etc/nginx/conf.d:ro,Z" \
  -v "$DATA/certs:/certs:ro,Z"

sleep 2
if podman exec nginx nginx -t 2>&1 | grep -q 'test is successful'; then
  say "nginx config test passed"
else
  warn "nginx -t failed:"; podman exec nginx nginx -t || true
fi
done_msg nginx "https://command.songofeo.com (and every other app hostname)"
echo "    After editing conf.d:  podman exec nginx nginx -t && podman exec nginx nginx -s reload"
