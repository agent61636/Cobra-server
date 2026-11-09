# shellcheck shell=bash
# Shared helpers for the Cobra podman run scripts. Sourced by every script, never run on its own.
#
# Settings any script honours (put them in front of the command, e.g. UPDATE=1 ./jellyfin.sh):
#   UPDATE=1        pull a newer image before recreating the container
#   COBRA_TZ=...    timezone for the containers (default: the host's)
#   RECREATE_POD=1  delete and recreate the pod (removes every container in it; run up-all.sh after)
#   SKIP_STATE_RESTORE=1  start an emptied app blank instead of restoring its snapshot (part 13)
# Extra environment for one container: put KEY=value lines in ~/.config/cobra/<container>.env

set -euo pipefail

COBRA_CONF=${COBRA_CONF:-$HOME/.config/cobra}
UPDATE=${UPDATE:-0}
DISKS=${COBRA_DISKS:-/srv/storage/disks}

# Which drive holds each folder (manual part 3.4, "Which drive holds what"). Paths are relative to $DISKS
# on the host and to /media inside the containers. Moved a folder to another drive? Change it here only.
# shellcheck disable=SC2034  # used by the scripts that source this file
{
  MOVIES_DIR=video/movies    # the wd1 + wd2 pool (part 3.4)
  FILLER_DIR=wd1/filler
  PREROLLS_DIR=wd1/pre-rolls
  SHOWS_DIR=video/series
  MUSIC_DIR=dock1a/music
  COMEDY_DIR=dock1a/comedy  # stand-up albums: Audiobookshelf library Comedy (comedy.)
  SESSIONS_DIR=dock1a/sessions  # The Ward, recorded podcasts: Audiobookshelf podcast library Sessions (sessions.)
  AUDIOBOOKS_DIR=dock1a/audiobooks
  BOOKS_DIR=dock1a/books
  COMICS_DIR=dock1a/comics
  SCANS_DIR=dock1a/scans
  BACKUPS_DIR=dock1a/backups
  ART_DIR=dock1a/art
  ROMS_DIR=dock1b/roms
  YOUTUBE_DIR=wd2/youtube
}

QUADLET_DIR=$HOME/.config/containers/systemd

host_tz() {
  if [ -r /etc/timezone ]; then cat /etc/timezone
  elif command -v timedatectl >/dev/null; then timedatectl show -p Timezone --value 2>/dev/null || echo UTC
  else echo UTC
  fi
}
COBRA_TZ=${COBRA_TZ:-$(host_tz)}

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Checks that we're podsvc in a real login session (systemd user services and rootless podman need one).
preflight() {
  [ "$(id -u)" -ne 0 ] || die "run this as podsvc, not root:  sudo machinectl shell podsvc@"
  [ "$(id -un)" = podsvc ] || warn "running as $(id -un); the manual runs every container as podsvc"
  command -v podman >/dev/null || die "podman isn't installed (part 3.3 / 5.2)"
  if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    die "no user session. Log in with  sudo machinectl shell podsvc@  (sudo su / sudo -u don't create one)"
  fi
  mkdir -p "$COBRA_CONF" && chmod 700 "$COBRA_CONF"
  start_at_boot
}

# Containers made with --restart always are started at boot by podman-restart.service (needs linger, part 3.5).
start_at_boot() {
  systemctl --user is-enabled --quiet podman-restart.service 2>/dev/null && return 0
  if systemctl --user enable podman-restart.service >/dev/null 2>&1; then
    say "enabled podman-restart.service: containers come back after a reboot"
  else
    warn "couldn't enable podman-restart.service; containers won't start at boot (check: loginctl show-user $(id -un) | grep Linger)"
  fi
}

# The scripts and the manual's Quadlet files must not both own a container.
no_quadlet() {
  local n
  for n in "$@"; do
    if [ -e "$QUADLET_DIR/$n" ]; then
      die "$n exists in $QUADLET_DIR, so systemd already runs this one from the manual's Quadlet setup.
       Use one or the other. To switch to the scripts:
         systemctl --user stop ${n%.*}$( [ "${n##*.}" = pod ] && echo -pod ) && rm $QUADLET_DIR/$n && systemctl --user daemon-reload"
    fi
  done
}

# ensure_pod NAME HOST:CONTAINER ...   Ports can only be set when the pod is created.
ensure_pod() {
  local name=$1; shift
  no_quadlet "$name.pod"
  if podman pod exists "$name"; then
    [ "${RECREATE_POD:-0}" = 1 ] || return 0
    say "RECREATE_POD=1: removing pod $name and everything in it"
    podman pod rm -f "$name" >/dev/null
  fi
  local args=() p
  for p in "$@"; do args+=(--publish "$p"); done
  say "creating pod $name (ports: $*)"
  podman pod create --name "$name" --infra-name "$name-infra" "${args[@]}" >/dev/null
}

# ensure_dir PATH ...   Makes app folders; they must be under a folder podsvc owns (/srv/stream, /srv/gate).
ensure_dir() {
  local d
  for d in "$@"; do
    mkdir -p "$d" 2>/dev/null || die "can't create $d as $(id -un). As eels: sudo mkdir -p $d && sudo chown $(id -un): $d"
  done
}

# need_folders FOLDER ...   Each folder's drive must be mounted, and the folder must exist.
# SGIN: every drive is its own mount at $DISKS/<label>. Gate: $DISKS itself is the CIFS mount of the SGIN's media share.
need_folders() {
  local f d
  ls "$DISKS" >/dev/null 2>&1 || die "$DISKS isn't reachable. SGIN: part 3.4. Gate: is the SGIN on? (part 5.2)"
  for f in "$@"; do
    d=${f%%/*}
    if ! mountpoint -q "$DISKS" && ! mountpoint -q "$DISKS/$d"; then
      die "$DISKS/$d is an empty folder, not the mounted $d drive. Plug it in and mount it first (part 3.4)"
    fi
    [ -d "$DISKS/$f" ] || mkdir -p "$DISKS/$f" 2>/dev/null || die "$DISKS/$f is missing and $(id -un) can't create it"
  done
}

random_hex() { od -An -tx1 -N"${1:-24}" /dev/urandom | tr -d ' \n'; }

# ensure_secret NAME [VALUE]   Creates a podman secret once (random unless VALUE is given) and never changes it.
# Read one back with:  podman secret inspect --showsecret --format '{{.SecretData}}' NAME
ensure_secret() {
  local name=$1 value=${2:-}
  podman secret exists "$name" && return 0
  [ -n "$value" ] || value=$(random_hex 24)
  printf %s "$value" | podman secret create "$name" - >/dev/null
  say "created secret $name"
}

# run_container NAME POD IMAGE [podman run options ...] [-- command ...]
# Removes any old container of that name and starts a fresh one. App data lives in the volumes, so this is safe.
run_container() {
  local name=$1 pod=$2 image=$3; shift 3
  local opts=() cmd=()
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then shift; cmd=("$@"); break; fi
    opts+=("$1"); shift
  done
  no_quadlet "$name.container"
  [ -f "$COBRA_CONF/$name.env" ] && opts+=(--env-file "$COBRA_CONF/$name.env")

  # Pull first, so a failed download leaves the running container alone.
  if [ "$UPDATE" = 1 ] || ! podman image exists "$image"; then
    say "pulling $image"
    podman pull -q "$image" >/dev/null
  fi
  podman rm -f --ignore "$name" >/dev/null
  say "starting $name"
  podman run -d --name "$name" --pod "$pod" --restart always --pull never \
    -e TZ="$COBRA_TZ" "${opts[@]}" "$image" "${cmd[@]}" >/dev/null
}

# wait_port PORT [SECONDS]   Waits until the pod answers on a published port (SGIN only; the gate publishes just 80/443).
wait_port() {
  local port=$1 secs=${2:-60} i
  for ((i = 0; i < secs; i++)); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

# done_msg NAME URL   Final lines every script prints.
done_msg() {
  say "$1 is running: $2"
  echo "    logs:    podman logs -f $1"
  echo "    restart: podman restart $1      update: UPDATE=1 $0"
}

# Personal-state snapshots (favorites, progress, per-user settings). Part 13.
# shellcheck source=state.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.sh"
