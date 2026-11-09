#!/usr/bin/env bash
# Restore personal state from the latest snapshot. Run as podsvc.
#   ./state-restore.sh                  # every gate app whose database is missing
#   ./state-restore.sh vaultwarden
#   FORCE_STATE_RESTORE=1 ./state-restore.sh vaultwarden
# Part 13.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

preflight
state_restore_cli gate "$@"
