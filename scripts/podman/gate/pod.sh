# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this
# The gate VM's "gate" pod (cobra-gate, 10.6.9.10). Sourced by the scripts in this folder.
# Only nginx's 80/443 are published. Every app listens on 127.0.0.1 inside the pod and is reached through nginx:
#   8222 Vaultwarden   8000 Paperless   8081 MeTube   3000 Homepage   3001 Uptime Kuma
#   8090 hiscore       9091 Authelia    5432 Postgres 6379 Redis   8790 eo-art
GATE_POD=gate
GATE_PORTS=(80:80 443:443)
GATE_DATA=${COBRA_DATA:-/srv/gate}

gate_pod() {
  # Read /proc directly: sysctl lives in /usr/sbin, which isn't on podsvc's PATH on Debian.
  [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo 1024)" -le 80 ] \
    || die "rootless podman can't bind 80/443 yet. As eels (part 5.2):
       echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/90-ports.conf && sudo sysctl --system"
  ensure_pod "$GATE_POD" "${GATE_PORTS[@]}"
}

# Inside the pod nothing is published, so checks run from a container that has curl or wget.
# pod_http URL [SECONDS]   Waits until URL answers, using the given container to ask.
pod_http() {
  local via=$1 url=$2 secs=${3:-60} i
  for ((i = 0; i < secs; i += 2)); do
    podman exec "$via" sh -c "command -v curl >/dev/null && curl -fsS -o /dev/null '$url' || wget -q -O /dev/null '$url'" 2>/dev/null && return 0
    sleep 2
  done
  return 1
}
