#!/usr/bin/env bats
# Unit tests. The nft and migration tests need Linux with nft and root (CI runs them in a
# debian:12 container with NET_ADMIN); elsewhere they are skipped.
# A bare `! cmd` never fails a test under set -e; negations use `run !`.

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=../geokordon
	source "$BATS_TEST_DIRNAME/../geokordon"
	set +u
	ETC_DIR="$BATS_TEST_TMPDIR/etc"
	CACHE="$BATS_TEST_TMPDIR/cache"
	ALLOW_FILE="$ETC_DIR/allow"
	PORTS_FILE="$ETC_DIR/ports"
	mkdir -p "$ETC_DIR" "$CACHE"
}

need_nft() {
	[ "$(id -u)" = 0 ] && command -v nft >/dev/null || skip "needs root and nft"
}

@test "command_valid accepts the documented commands only" {
	command_valid install
	command_valid install --with-warp
	command_valid install --without-warp
	command_valid update
	command_valid status
	command_valid warp on
	command_valid warp up
	command_valid allow add a.ru 1.2.3.4
	command_valid allow list
	command_valid allow push file
	command_valid remove
	run ! command_valid install --warp
	run ! command_valid install --with-warp extra
	run ! command_valid warp
	run ! command_valid allow add
	run ! command_valid allow push
	run ! command_valid allow sync
	run ! command_valid bogus
}

@test "no arguments print usage with exit 2, --help exits 0" {
	run "$BATS_TEST_DIRNAME/../geokordon"
	[ "$status" = 2 ]
	[[ "$output" == Usage:* ]]
	run "$BATS_TEST_DIRNAME/../geokordon" --help
	[ "$status" = 0 ]
	run "$BATS_TEST_DIRNAME/../geokordon" --version
	[ "$output" = "geokordon $GEOKORDON_VERSION" ]
}

@test "allow_check: addresses, subnets and host names" {
	local entry
	for entry in bbc.de fb.ee example.ru a-b.c 8.8.8.8 10.0.0.0/8 2001:db8::/32 ::1; do
		(allow_check "$entry") || {
			echo "rejected $entry"
			return 1
		}
	done
	for entry in 999.1.1.1 1.2.3 -x.ru a..b 1.2.3.4/33 ::1/129 'a b' 'x;y'; do
		if (allow_check "$entry" 2>/dev/null); then
			echo "accepted $entry"
			return 1
		fi
	done
}

@test "allow_resolve: hex-letter host names resolve, invalid entries are skipped" {
	getent() { echo "192.0.2.7 STREAM $2"; }
	printf '%s\n' '# comment' 'bbc.de  # inline' 8.8.8.8 1.2.3 '' 2001:db8::/32 >"$ALLOW_FILE"
	run --separate-stderr allow_resolve
	[ "$status" = 0 ]
	[ "$output" = "$(printf '%s\n' 192.0.2.7 8.8.8.8 2001:db8::/32)" ]
	[[ "$stderr" == *"skipped, not a host, IP or subnet: 1.2.3"* ]]
}

@test "allow add, del and push keep comments and report changes" {
	printf '%s\n' '# keep me' 1.1.1.1 >"$ALLOW_FILE"
	run allow_add 1.1.1.1 example.ru
	[ "${lines[0]}" = "already listed: 1.1.1.1" ]
	[ "${lines[1]}" = "added: example.ru" ]
	allow_del 1.1.1.1 >/dev/null
	[ "$(cat "$ALLOW_FILE")" = "$(printf '%s\n' '# keep me' example.ru)" ]
	printf '%s\n' example.ru 2.2.2.2 >"$BATS_TEST_TMPDIR/new"
	run allow_push "$BATS_TEST_TMPDIR/new"
	[ "$output" = "added: 2.2.2.2" ]
	[ "$(allow_entries)" = "$(printf '%s\n' example.ru 2.2.2.2)" ]
}

@test "allow_push rejects a file with an invalid entry and keeps the list" {
	echo 1.1.1.1 >"$ALLOW_FILE"
	printf '%s\n' 2.2.2.2 1.2.3 >"$BATS_TEST_TMPDIR/new"
	run allow_push "$BATS_TEST_TMPDIR/new"
	[ "$status" = 1 ]
	[ "$(cat "$ALLOW_FILE")" = 1.1.1.1 ]
}

zone() {
	local n="$1" i
	for ((i = 0; i < n; i++)); do echo "10.$((i / 256)).$((i % 256)).0/24"; done
}

@test "prefix_fetch: a good list replaces the cache, a short or malformed one does not" {
	curl() {
		local out
		while [ $# -gt 0 ]; do
			[ "$1" = -o ] && out="$2"
			shift
		done
		cp "$SRC" "$out"
	}
	local file="$CACHE/ru4.zone"
	zone 3000 >"$BATS_TEST_TMPDIR/full"
	SRC="$BATS_TEST_TMPDIR/full" prefix_fetch u "$file" "$V4_PREFIX" 1000
	[ "$(wc -l <"$file")" -eq 3000 ]

	zone 1400 >"$BATS_TEST_TMPDIR/half"
	SRC="$BATS_TEST_TMPDIR/half" prefix_fetch u "$file" "$V4_PREFIX" 1000 2>/dev/null
	[ "$(wc -l <"$file")" -eq 3000 ]

	{
		zone 2900
		echo '10.1.'
	} >"$BATS_TEST_TMPDIR/cut"
	SRC="$BATS_TEST_TMPDIR/cut" prefix_fetch u "$file" "$V4_PREFIX" 1000 2>/dev/null
	[ "$(wc -l <"$file")" -eq 3000 ]

	rm "$file"
	zone 500 >"$BATS_TEST_TMPDIR/tiny"
	SRC="$BATS_TEST_TMPDIR/tiny" prefix_fetch u "$file" "$V4_PREFIX" 1000 2>/dev/null
	[ ! -e "$file" ]
}

@test "ports_from_bindings turns docker inspect lines into proto and port" {
	run ports_from_bindings < <(printf '%s\n' '80/tcp 41010' '41000/udp 41000' '51820/udp ' '')
	[ "$output" = "$(printf '%s\n' 'tcp 41010' 'udp 41000')" ]
}

@test "ports_all: manual ports, sshd, ssh.socket and containers, recounted" {
	sshd() { printf '%s\n' 'port 22' 'addressfamily any'; }
	ss() { echo 'LISTEN 0 128 0.0.0.0:2222 0.0.0.0:* users:(("sshd",pid=1,fd=3))'; }
	systemctl() { echo '[::]:2200 (Stream)'; }
	docker() {
		case "$1" in
		ps) printf '%s\n' amnezia-awg other ;;
		inspect) [ "$4" = amnezia-awg ] && printf '%s\n' '41000/udp 41000' '41001/udp 41001' ;;
		esac
	}
	printf '%s\n' '# manual' 'udp  51820' 'bogus' >"$PORTS_FILE"
	run ports_all
	[ "$output" = "$(printf '%s\n' 'tcp 22' 'tcp 2200' 'tcp 2222' 'udp 41000' 'udp 41001' 'udp 51820')" ]
}

@test "rules_generate passes nft -c" {
	need_nft
	local v4="2.56.24.0/22,5.8.0.0/16" v6="2001:640::/32" allow4="8.8.8.8,10.0.0.1/8" allow6="" tcp="22" udp="41000,41001"
	rules_generate >"$BATS_TEST_TMPDIR/rules.nft"
	nft -c -f "$BATS_TEST_TMPDIR/rules.nft"
}

@test "rules_generate without v6, allow or udp passes nft -c" {
	need_nft
	local v4="2.56.24.0/22" v6="" allow4="" allow6="" tcp="22" udp=""
	rules_generate >"$BATS_TEST_TMPDIR/rules.nft"
	nft -c -f "$BATS_TEST_TMPDIR/rules.nft"
}

@test "install_migrate moves the 0.3.x state" {
	[ "$(id -u)" = 0 ] && [ "$(uname -s)" = Linux ] || skip "needs root on Linux"
	echo 1.1.1.1 >/etc/geokordon.allow
	echo 'tcp 22' >/etc/geokordon.ports
	mkdir -p /etc/geokordon-warp /usr/local/sbin
	echo profile >/etc/geokordon-warp/wgcf-profile.conf
	touch /usr/local/sbin/geokordon-update /usr/local/sbin/geokordon-warp
	WARP_DIR="$ETC_DIR/warp"
	install_migrate
	[ "$(cat "$ALLOW_FILE")" = 1.1.1.1 ]
	[ "$(cat "$PORTS_FILE")" = 'tcp 22' ]
	[ "$(cat "$WARP_DIR/wgcf-profile.conf")" = profile ]
	[ ! -e /etc/geokordon.allow ] && [ ! -e /etc/geokordon.ports ] && [ ! -e /etc/geokordon-warp ]
	[ ! -e /usr/local/sbin/geokordon-update ] && [ ! -e /usr/local/sbin/geokordon-warp ]
}

@test "front_script runs the program with the same arguments, through sudo when not root" {
	self_bundle() { printf '%s\n' 'printf "%s\n" "$@" >"$OUT"'; }
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '%s\n' '#!/bin/sh' 'echo sudo >"$OUT.sudo"' '[ "$1" = -n ] && shift' 'exec "$@"' >"$BATS_TEST_TMPDIR/bin/sudo"
	printf '%s\n' '#!/bin/sh' 'echo 1000' >"$BATS_TEST_TMPDIR/bin/id"
	chmod +x "$BATS_TEST_TMPDIR/bin/sudo" "$BATS_TEST_TMPDIR/bin/id"
	export OUT="$BATS_TEST_TMPDIR/args"
	PATH="$BATS_TEST_TMPDIR/bin:$PATH" sh -c "$(front_script allow add "it's" '$(touch x)' 'two words' '"q"')" </dev/null
	[ "$(cat "$OUT")" = "$(printf '%s\n' allow add "it's" '$(touch x)' 'two words' '"q"')" ]
	[ -f "$OUT.sudo" ]
	[ ! -e x ]
}

@test "front_script carries the file of allow push" {
	self_bundle() { printf '%s\n' 'cp "$3" "$OUT"'; }
	printf '%s\n' example.ru 1.1.1.1 >"$BATS_TEST_TMPDIR/list"
	export OUT="$BATS_TEST_TMPDIR/pushed"
	sh -c "$(front_script allow push "$BATS_TEST_TMPDIR/list" | sed 's/sudo -n //; s/sudo //')" </dev/null
	cmp "$BATS_TEST_TMPDIR/list" "$OUT"
}

@test "the build inlines modules and units and keeps the program working" {
	local out="$BATS_TEST_TMPDIR/geokordon" unit
	"$BATS_TEST_DIRNAME/../scripts/build" "$out" >/dev/null
	run bash "$out" --version
	[ "$output" = "geokordon $GEOKORDON_VERSION" ]
	run ! grep -q 'GEOKORDON_ROOT/lib' "$out"
	for unit in "$BATS_TEST_DIRNAME"/../units/*; do
		diff <(bash -c "source '$out'; unit_text $(basename "$unit")") "$unit"
	done
}
