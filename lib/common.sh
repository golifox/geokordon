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

# need_packages PACKAGE...: install the missing packages with apt (Debian, Ubuntu) or dnf
# (Rocky, Alma, RHEL, Fedora); the names are the same on both.
need_packages() {
	local missing=() package
	if command -v apt-get >/dev/null; then
		for package in "$@"; do
			dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
		done
		[ ${#missing[@]} -gt 0 ] || return 0
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y -qq "${missing[@]}" >/dev/null
	elif command -v dnf >/dev/null; then
		for package in "$@"; do
			# --whatprovides: RHEL ships curl as curl-minimal, which conflicts with curl.
			rpm -q --whatprovides "$package" >/dev/null 2>&1 || missing+=("$package")
		done
		[ ${#missing[@]} -gt 0 ] || return 0
		dnf install -y -q "${missing[@]}" >/dev/null
	else
		die "Neither apt-get nor dnf found: install $* by hand, then run again"
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
