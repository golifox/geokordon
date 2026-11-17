# shellcheck shell=bash
# status: what is installed and applied, read-only.

cmd_status() {
	local installed="not installed" last
	if [ -x "$BIN" ]; then installed="$("$BIN" --version)"; fi
	echo "Installed: $installed (running $GEOKORDON_VERSION)"
	echo "Timer: $(systemctl is-active geokordon.timer 2>/dev/null || true), boot restore: $(systemctl is-enabled geokordon-restore.service 2>/dev/null || true)"
	last="$(date -r "$NFT_FILE" '+%F %T %Z' 2>/dev/null || true)"
	echo "Rules generated: ${last:-never}; last timer run: $(systemctl show -p Result --value geokordon.service 2>/dev/null || true)"
	if nft list table inet geokordon >/dev/null 2>&1; then
		echo "Geoblock: on, $(nft list set inet geokordon ru4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | wc -l | tr -d ' ') IPv4 ranges"
	else
		echo "Geoblock: off"
	fi
	if [ -s "$CACHE/ports" ]; then
		echo "Open for RU: $(paste -sd, - <"$CACHE/ports" | sed 's/,/, /g')"
	fi
	allow_show
	if systemctl is-active --quiet geokordon-warp.service; then
		echo "WARP: on"
	else
		echo "WARP: off"
	fi
}
