#!/usr/bin/env bash
# Cobra N.A.V. cloning vat. On the SGIN, as podsvc (sudo machinectl shell podsvc@):
#   ./nav.sh             list every N.A.V. on the switchboard and check its folders
#   ./nav.sh build NAME  (re)build one N.A.V. from the switchboard and restart it
#   ./nav.sh build all   every N.A.V. on the switchboard
# Each N.A.V. is its own Navidrome (own users, playlists, plays) that sees ONLY the folders switched on
# for it, each mounted read-only from the one shared dock1a/music. Inside the container a folder keeps
# its real path (/media/dock1a/music/eels/pop), so a song has the same path in every N.A.V.
# Backs up a Quadlet file before replacing it, shows the change and asks first (YES=1 skips the question).
set -euo pipefail
SB=${SB:-/srv/stream/navs/switchboard.conf}
Q=${QUADLET_DIR:-$HOME/.config/containers/systemd}
DISKS=${COBRA_DISKS:-/srv/storage/disks}
MUSIC=dock1a/music
DATA=${COBRA_DATA:-/srv/stream}
IMAGE=${NAVIDROME_IMAGE:-docker.io/deluan/navidrome:latest}
TS=$(date +%Y%m%d-%H%M%S)
say()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$SB" ] || die "no switchboard at $SB. Copy switchboard.example.conf there first (see README)"

# names: every [block] on the switchboard
names() { sed -nE 's/^\[([a-z0-9-]+)\][[:space:]]*$/\1/p' "$SB"; }
# get NAME KEY: every value of KEY in NAME's block, one per line
get() {
  awk -v want="$1" -v key="$2" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^\[/ { inb = ($0 ~ "^\\[" want "\\][[:space:]]*$"); next }
    inb { k=$0; sub(/[[:space:]]*=.*/, "", k); gsub(/^[[:space:]]+/, "", k)
          if (k == key) { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v); print v } }' "$SB"
}
one() { get "$1" "$2" | head -n1; }

check() {  # check NAME: validates a block, prints problems, returns 1 if any
  local n=$1 bad=0 p f
  p=$(one "$n" port)
  [[ $p =~ ^45(3[3-9]|4[0-9])$ ]] || { warn "[$n] port '$p' isn't 4533-4549"; bad=1; }
  [ -n "$(one "$n" host)" ] || { warn "[$n] has no host"; bad=1; }
  [ -n "$(get "$n" on)" ] || { warn "[$n] has nothing switched on"; bad=1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "*" ] && continue
    case $f in /*|*..*|*:*|*,*) warn "[$n] '$f': no leading /, '..', ':' or ','"; bad=1; continue ;; esac
    [ -d "$DISKS/$MUSIC/$f" ] || { warn "[$n] $MUSIC/$f doesn't exist (check spelling and capitals)"; bad=1; }
  done < <(get "$n" on)
  local dup; dup=$(for x in $(names); do one "$x" port; done | sort | uniq -d)
  [ -z "$dup" ] || { warn "port $dup is used by two N.A.V.s"; bad=1; }
  return $bad
}

list() {
  mountpoint -q "$DISKS/dock1a" || warn "dock1a isn't mounted; folder checks will fail"
  local n
  for n in $(names); do
    printf '\n\033[1m%s\033[0m  :%s  %s.songofeo.com  (user %s, container %s)\n' "$n" "$(one "$n" port)" \
      "$(one "$n" host)" "$(u=$(one "$n" user); echo "${u:-$n}")" "$(c=$(one "$n" container); echo "${c:-navidrome-$n}")"
    get "$n" on | sed 's/^/    on  /'
    check "$n" && echo "    OK"
  done
}

quadlet() {  # quadlet NAME CONTAINER PORT: prints the .container file
  local n=$1 c=$2 p=$3 f
  printf '%s\n' "# Cobra N.A.V. [$n], made by nav.sh from $SB. Edit the switchboard, not this file." \
    "[Container]" "ContainerName=$c" "Image=$IMAGE" "Pod=stream.pod" "AutoUpdate=registry" \
    "Environment=ND_PORT=$p ND_SESSIONTIMEOUT=8h ND_MUSICFOLDER=/media/$MUSIC ND_REVERSEPROXYWHITELIST=10.6.9.10/32 ND_ENABLEINSIGHTSCOLLECTOR=false" \
    "Volume=$DATA/$c:/data:Z"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f=${f//%/%%}   # systemd reads % as a specifier
    if [ "$f" = "*" ]; then echo "Volume=$DISKS/$MUSIC:/media/$MUSIC:ro"
    else echo "Volume=$DISKS/$MUSIC/$f:/media/$MUSIC/$f:ro"; fi
  done < <(get "$n" on)
  printf '%s\n' "[Install]" "WantedBy=default.target"
}

build() {
  local n=$1 c p file new
  grep -qx "\[$n\]" <(sed 's/[[:space:]]*$//' "$SB") || die "no [$n] block in $SB"
  check "$n" || die "[$n] has problems (above); nothing changed"
  c=$(one "$n" container); c=${c:-navidrome-$n}
  p=$(one "$n" port)
  [[ $c =~ ^navidrome(-[a-z0-9-]+)?$ ]] || die "[$n] container '$c' must be navidrome or navidrome-something"
  local pub="$p:$p"; [ "$p" -ge 4537 ] && pub="4537-4549:4537-4549"
  grep -qx "PublishPort=$pub" "$Q/stream.pod" 2>/dev/null \
    || die "stream.pod doesn't publish :$p. Clone slots 4537-4549: run nav-vat.sh once as eels"
  file=$Q/$c.container
  new=$(mktemp); quadlet "$n" "$c" "$p" > "$new"
  if [ -f "$file" ]; then
    if cmp -s "$file" "$new"; then echo "[$n] $c.container already matches the switchboard"
    else
      say "[$n] changes to $c.container:"
      diff -u "$file" "$new" || true
      if [ "${YES:-0}" != 1 ]; then
        read -rp "Replace $c.container (a backup is kept)? [y/N] " a </dev/tty
        [[ $a =~ ^[Yy]$ ]] || { rm -f "$new"; echo "skipped [$n]"; return 0; }
      fi
      cp -p "$file" "$file.bak-$TS"; echo "backup: $file.bak-$TS"
      cat "$new" > "$file"
    fi
  else
    mkdir -p "$Q" "$DATA/$c"
    cat "$new" > "$file"; echo "wrote $file"
  fi
  rm -f "$new"
  mkdir -p "$DATA/$c"
  [ -n "${TEST:-}" ] && return 0
  systemctl --user daemon-reload
  say "[$n] restarting $c (it rescans the switched-on folders)"
  systemctl --user restart "$c.service"
  local ok=; for _ in $(seq 60); do (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { ok=1; break; }; sleep 2; done
  [ -n "$ok" ] && echo "    OK  http://10.6.9.20:$p" || warn "$c isn't answering on :$p: journalctl --user -u $c -n 50"
}

case ${1:-list} in
  list) list ;;
  build) [ -n "${2:-}" ] || die "./nav.sh build NAME   (or: build all)"
         if [ "$2" = all ]; then for n in $(names); do build "$n"; done; else build "$2"; fi ;;
  *) die "./nav.sh [list | build NAME | build all]" ;;
esac
