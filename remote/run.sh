#!/usr/bin/env bash
# Entry point on the server, run as root from a temporary copy of remote/:
#   run.sh SSH_PORT install | remove | warp on|off
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
exec </dev/null
# ssh forwards the local locale, which the server may not have.
export LANG=C.UTF-8 LC_ALL=C.UTF-8

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
trap 'rm -rf "$DIR"' EXIT

[ "$(id -u)" = 0 ] || {
	echo "Needs root or sudo" >&2
	exit 1
}

SSH_PORT="$1"
shift

source "$DIR/common.sh"
source "$DIR/install.sh"
source "$DIR/warp.sh"
source "$DIR/remove.sh"

case "$1" in
install) install_ru_block ;;
remove) remove_ru_block ;;
warp) "warp_$2" ;;
esac
