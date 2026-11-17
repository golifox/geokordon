# shellcheck shell=bash
# Paths and helpers shared by every command.

ETC_DIR=/etc/geokordon
CACHE=/var/lib/geokordon
BIN=/usr/local/sbin/geokordon
UNIT_DIR=/etc/systemd/system
LOCK=/run/geokordon.lock

die() {
	echo "$*" >&2
	exit 1
}

# need_root: core commands change the firewall and systemd.
need_root() {
	[ "$(id -u)" = 0 ] || die "Needs root: run with sudo, or pass -H user@host to work on a remote server"
}

need_installed() {
	[ -x "$BIN" ] && [ -f "$UNIT_DIR/geokordon.service" ] || die "geokordon is not installed: run geokordon install first"
}

# lock: one changing command at a time, the timer included. Held until the process exits.
lock() {
	exec 9>"$LOCK"
	flock 9
}

# need_packages PACKAGE...: install the missing Debian/Ubuntu packages.
need_packages() {
	local missing=() package
	for package in "$@"; do
		dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y -qq "${missing[@]}" >/dev/null
	fi
}

# self_bundle: this program as one file on stdout; from sources it is built on the fly.
self_bundle() {
	if [ -n "${GEOKORDON_BUNDLED:-}" ]; then
		cat "$GEOKORDON_SELF"
	else
		"$GEOKORDON_ROOT/scripts/build" -
	fi
}
