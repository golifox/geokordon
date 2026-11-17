# shellcheck shell=bash
# remove: undo install and warp.

remove_ru_block() {
	warp_purge

	systemctl disable --now ru-block.timer 2>/dev/null || true
	nft delete table inet ru_block 2>/dev/null || true
	rm -f /etc/systemd/system/ru-block.service /etc/systemd/system/ru-block.timer \
		/usr/local/sbin/ru-block-update /etc/ru-block.ports
	rm -rf /var/lib/ru-block
	systemctl daemon-reload
	echo "ru-block removed"
}
