# shellcheck shell=bash
# status: what is installed and applied, read-only.

# geo_ranges: the number of IPv4 ranges in the applied table.
geo_ranges() {
	nft list set inet geokordon geo4 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | wc -l | tr -d ' '
}

cmd_status() {
	local installed="not installed" last
	if [ -x "$BIN" ]; then installed="$("$BIN" --version)"; fi
	echo "Installed: $installed (running $GEOKORDON_VERSION)"
	echo "Timer: $(systemctl is-active geokordon.timer 2>/dev/null || true), boot restore: $(systemctl is-enabled geokordon-restore.service 2>/dev/null || true)"
	last="$(date -r "$NFT_FILE" '+%F %T %Z' 2>/dev/null || true)"
	echo "Rules generated: ${last:-never}; last timer run: $(systemctl show -p Result --value geokordon.service 2>/dev/null || true)"
	echo "Blocked countries: $COUNTRIES; containers: $CONTAINERS"
	if nft list table inet geokordon >/dev/null 2>&1; then
		echo "Geoblock: on, $(geo_ranges) IPv4 ranges"
	else
		echo "Geoblock: off"
	fi
	if [ -s "$CACHE/ports" ]; then
		echo "Open to them: $(paste -sd, - <"$CACHE/ports" | sed 's/,/, /g')"
	fi
	allow_show
	# After a boot the WARP unit waits for Docker; enabled but not yet active is not off.
	if systemctl is-active --quiet geokordon-warp.service; then
		echo "WARP: on"
	elif systemctl is-enabled --quiet geokordon-warp.service 2>/dev/null; then
		echo "WARP: enabled, starting (after Docker) or failed: systemctl status geokordon-warp"
	else
		echo "WARP: off"
	fi
}
