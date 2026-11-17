# shellcheck shell=bash
# remove: undo install and warp, this program included.

cmd_remove() {
	local unit
	# The list lives only here: leave a copy in the terminal.
	if [ -n "$(allow_entries)" ]; then
		echo "Direct list being removed:"
		allow_entries | sed 's/^/  /'
	fi
	warp_purge
	systemctl disable --now geokordon.timer 2>/dev/null || true
	systemctl disable geokordon-restore.service 2>/dev/null || true
	nft delete table inet geokordon 2>/dev/null || true
	for unit in "${UNITS[@]}"; do rm -f "${UNIT_DIR:?}/$unit"; done
	rm -f "$BIN"
	rm -rf "${ETC_DIR:?}" "${CACHE:?}"
	systemctl daemon-reload
	echo "geokordon removed"
}
