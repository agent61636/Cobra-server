#!/usr/bin/env bash
# Restore personal state from the latest snapshot. Run as podsvc.
#   ./state-restore.sh                  # every SGIN app whose database is missing
#   ./state-restore.sh navidrome
#   FORCE_STATE_RESTORE=1 ./state-restore.sh navidrome   # move the live directory aside first
# Part 13. SKIP_STATE_RESTORE=1 on an app script starts that app empty instead.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

preflight
state_restore_cli sgin "$@"
