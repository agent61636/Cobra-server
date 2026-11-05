#!/usr/bin/env bash
# Starts (or, with UPDATE=1, updates) every app on the gate, in order. Run as podsvc.
# One app failing (most often Paperless, MeTube or eo-art while the SGIN's share isn't mounted) doesn't stop
# the rest: nginx and Authelia still start, so every other hostname keeps working. Failures are listed at the end.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failed=()
for s in authelia vaultwarden paperless metube homepage uptime-kuma hiscore eo-art nginx; do
  "$here/$s.sh" || failed+=("$s")
  echo
done
podman ps --pod --format 'table {{.Names}}\t{{.Status}}\t{{.PodName}}'
if [ ${#failed[@]} -gt 0 ]; then
  printf '\n\033[31mThese did not start:\033[0m %s\n' "${failed[*]}"
  echo "Scroll up for each one's ERROR line, fix it, then run just that script again (e.g. ./${failed[0]}.sh)."
  exit 1
fi
echo
echo "All started. Check every hostname with:  $here/check.sh"
