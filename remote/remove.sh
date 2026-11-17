# shellcheck shell=bash
# remove: undo install and warp.

remove_geokordon() {
	warp_purge

	systemctl disable --now geokordon.timer 2>/dev/null || true
	systemctl disable geokordon-restore.service 2>/dev/null || true
	nft delete table inet geokordon 2>/dev/null || true
	rm -f /etc/systemd/system/geokordon.service /etc/systemd/system/geokordon.timer \
		/etc/systemd/system/geokordon-restore.service \
		/usr/local/sbin/geokordon-update /etc/geokordon.ports "$ALLOW_FILE"
	rm -rf /var/lib/geokordon
	systemctl daemon-reload
	echo "geokordon removed"
}
