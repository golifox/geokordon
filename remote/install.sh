# shellcheck shell=bash
# install: nftables geoblock with a daily refresh. Uses DIR and SSH_PORT from run.sh.

install_ru_block() {
	need_packages nftables curl

	# The port we are connected through always stays open.
	echo "tcp $SSH_PORT" >>/etc/ru-block.ports

	install -m 755 "$DIR/files/ru-block-update" /usr/local/sbin/ru-block-update
	install -m 644 "$DIR/files/ru-block.service" "$DIR/files/ru-block.timer" /etc/systemd/system/
	systemctl daemon-reload
	/usr/local/sbin/ru-block-update
	systemctl enable --now ru-block.timer >/dev/null 2>&1
	echo "IPv4 ranges loaded: $(nft list set inet ru_block ru4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | wc -l)"
}
