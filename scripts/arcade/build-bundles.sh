#!/usr/bin/env bash
# Builds the two bundles for the arcade runbook (docs/arcade-runbook.md):
#   arcade-sgin.tar.gz   -> /tmp/cobra-arcade/ on the SGIN
#   arcade-cabinet.zip   -> C:\Cobra\setup\ on the cabinet
# Usage: scripts/arcade/build-bundles.sh [output folder]   (default: ./dist)
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=$(mkdir -p "${1:-dist}" && cd "${1:-dist}" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cobra-arcade/podman/sgin"
cp "$here"/sgin/*.sh "$tmp/cobra-arcade/"
cp "$here/../podman/lib.sh" "$tmp/cobra-arcade/podman/"
cp "$here/../podman/sgin/pod.sh" "$here/../podman/sgin/romm.sh" "$tmp/cobra-arcade/podman/sgin/"
chmod +x "$tmp"/cobra-arcade/*.sh "$tmp"/cobra-arcade/podman/sgin/*.sh
tar -C "$tmp" -czf "$out/arcade-sgin.tar.gz" cobra-arcade
mkdir -p "$tmp/cab"
for f in "$here"/cabinet/*.ps1; do sed 's/\r*$/\r/' "$f" >"$tmp/cab/$(basename "$f")"; done
(cd "$tmp/cab" && python3 -c 'import sys,zipfile,os
z=zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED)
[z.write(f) for f in sorted(os.listdir("."))]' "$out/arcade-cabinet.zip")
echo "wrote $out/arcade-sgin.tar.gz and $out/arcade-cabinet.zip"
