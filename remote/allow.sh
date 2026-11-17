# shellcheck shell=bash
# Direct list: hosts, IPs and subnets that skip the geoblock and WARP, so IP whitelists on
# those servers see the VPN server's own stable IP. Uses DIR from run.sh.

ALLOW_FILE=/etc/geokordon.allow

# allow_install: take allow.list from the uploaded copy, when the caller sent one.
allow_install() {
	if [ -f "$DIR/allow.list" ]; then
		install -m 644 "$DIR/allow.list" "$ALLOW_FILE"
	fi
}

# allow_sync (./geokordon allow sync|add|del): replace the list and apply it now.
allow_sync() {
	[ -x /usr/local/sbin/geokordon-update ] || {
		echo "geokordon is not installed: run ./geokordon install first" >&2
		exit 1
	}
	allow_install
	# Installed helpers may predate the direct list; refresh them from this copy.
	install -m 755 "$DIR/files/geokordon-update" /usr/local/sbin/geokordon-update
	if [ -x /usr/local/sbin/geokordon-warp ]; then
		install -m 755 "$DIR/files/geokordon-warp" /usr/local/sbin/geokordon-warp
	fi
	/usr/local/sbin/geokordon-update >/dev/null
	allow_show
}

# allow_list (./geokordon allow list): the list as the server has it, and what it resolved to.
allow_list() {
	if [ ! -s "$ALLOW_FILE" ]; then
		echo "Direct list on the server is empty"
		return
	fi
	echo "Direct list on the server:"
	sed 's/^/  /' "$ALLOW_FILE"
	allow_show
}

allow_show() {
	if [ -s /var/lib/geokordon/allow.resolved ]; then
		echo "Direct addresses (no geoblock, no WARP):"
		sed 's/^/  /' /var/lib/geokordon/allow.resolved
	else
		echo "No direct addresses"
	fi
}
