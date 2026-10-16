#!/usr/bin/env bash
# Starts (or, with UPDATE=1, updates) every app on the gate, in order. Run as podsvc.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for s in authelia vaultwarden paperless metube homepage uptime-kuma hiscore nginx; do
  "$here/$s.sh"
  echo
done
podman ps --pod --format 'table {{.Names}}\t{{.Status}}\t{{.PodName}}'
