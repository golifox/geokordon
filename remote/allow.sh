# shellcheck shell=bash
# Direct list: hosts, IPs and subnets that skip the geoblock and WARP, so IP whitelists on
# those servers see the VPN server's own stable IP. Uses DIR from run.sh.

ALLOW_FILE=/etc/ru-block.allow

# allow_install: take allow.list from the uploaded copy, when the caller sent one.
allow_install() {
	if [ -f "$DIR/allow.list" ]; then
		install -m 644 "$DIR/allow.list" "$ALLOW_FILE"
	fi
}

# allow_sync (./ru-block allow sync|add|del): replace the list and apply it now.
allow_sync() {
	[ -x /usr/local/sbin/ru-block-update ] || {
		echo "ru-block is not installed: run ./ru-block install first" >&2
		exit 1
	}
	allow_install
	# Installed helpers may predate the direct list; refresh them from this copy.
	install -m 755 "$DIR/files/ru-block-update" /usr/local/sbin/ru-block-update
	if [ -x /usr/local/sbin/ru-block-warp ]; then
		install -m 755 "$DIR/files/ru-block-warp" /usr/local/sbin/ru-block-warp
	fi
	/usr/local/sbin/ru-block-update >/dev/null
	allow_show
}

# allow_list (./ru-block allow list): the list as the server has it, and what it resolved to.
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
	if [ -s /var/lib/ru-block/allow.resolved ]; then
		echo "Direct addresses (no geoblock, no WARP):"
		sed 's/^/  /' /var/lib/ru-block/allow.resolved
	else
		echo "No direct addresses"
	fi
}
