# shellcheck shell=bash
# install [--with-warp|--without-warp]: this program in /usr/local/sbin, the units, the
# geoblock with a daily refresh, then WARP on or off when asked.

UNITS=(geokordon.service geokordon.timer geokordon-restore.service)

cmd_install() {
	need_packages nftables curl
	install_migrate
	self_install
	update_apply
	systemctl enable --now geokordon.timer >/dev/null 2>&1
	# Not started now: the table is already loaded; it loads the cache on the next boot.
	systemctl enable geokordon-restore.service >/dev/null 2>&1
	echo "IPv4 ranges loaded: $(grep -c . "$CACHE/ru4.zone")"
	allow_show

	# Without a flag WARP stays as it is, so a rerun to update never flips it.
	case "${1:-}" in
	--with-warp) warp_on ;;
	--without-warp) warp_off ;;
	esac
}

# self_install: this program and its units, as the units call the installed copy.
self_install() {
	local unit
	mkdir -p "$(dirname "$BIN")" "$ETC_DIR"
	self_bundle >"$BIN.new"
	chmod 755 "$BIN.new"
	mv "$BIN.new" "$BIN"
	for unit in "${UNITS[@]}"; do unit_text "$unit" >"$UNIT_DIR/$unit"; done
	# The WARP unit exists only once WARP was set up.
	if [ -f "$WARP_UNIT" ]; then unit_text geokordon-warp.service >"$WARP_UNIT"; fi
	systemctl daemon-reload
}

# self_sync: run from elsewhere (the front's copy), refresh an installed copy of another version.
self_sync() {
	[ -x "$BIN" ] || return 0
	[ "$GEOKORDON_SELF" -ef "$BIN" ] && return 0
	cmp -s "$BIN" <(self_bundle) || self_install
}

# install_migrate: move the state of 0.3.x to /etc/geokordon and drop its helpers.
install_migrate() {
	mkdir -p "$ETC_DIR"
	if [ -f /etc/geokordon.allow ] && [ ! -e "$ALLOW_FILE" ]; then mv /etc/geokordon.allow "$ALLOW_FILE"; fi
	if [ -f /etc/geokordon.ports ] && [ ! -e "$PORTS_FILE" ]; then mv /etc/geokordon.ports "$PORTS_FILE"; fi
	if [ -d /etc/geokordon-warp ] && [ ! -e "$WARP_DIR" ]; then mv /etc/geokordon-warp "$WARP_DIR"; fi
	rm -f /etc/geokordon.allow /etc/geokordon.ports /usr/local/sbin/geokordon-update /usr/local/sbin/geokordon-warp
}
