#!/usr/bin/env bash
# Snapshot personal state for every app on the SGIN. Run as podsvc.
# The first run also enables a daily user timer at 03:10. STATE_NO_TIMER=1 skips that.
# Part 13.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib.sh
. "$here/../lib.sh"
# shellcheck source=pod.sh
. "$here/pod.sh"

preflight
failed=0
state_backup_host sgin || failed=1
state_install_timer "$here/state-backup.sh"
exit "$failed"
