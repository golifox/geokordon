# shellcheck shell=bash
# install [--with-warp|--without-warp]: nftables geoblock with a daily refresh, then WARP
# on or off when asked. Uses DIR and SSH_PORT from run.sh.

install_geokordon() {
	need_packages nftables curl

	# The port we are connected through always stays open.
	echo "tcp $SSH_PORT" >>/etc/geokordon.ports
	allow_install

	install -m 755 "$DIR/files/geokordon-update" /usr/local/sbin/geokordon-update
	install -m 644 "$DIR/files/geokordon.service" "$DIR/files/geokordon.timer" /etc/systemd/system/
	systemctl daemon-reload
	/usr/local/sbin/geokordon-update
	systemctl enable --now geokordon.timer >/dev/null 2>&1
	echo "IPv4 ranges loaded: $(nft list set inet geokordon ru4 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?' | wc -l)"
	allow_show

	# Without a flag WARP stays as it is, so a rerun to update never flips it.
	case "${1:-}" in
	--with-warp) warp_on ;;
	--without-warp) warp_off ;;
	esac
}
