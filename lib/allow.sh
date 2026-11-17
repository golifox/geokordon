# shellcheck shell=bash
# Direct list: hosts, IPs and subnets that skip the geoblock and WARP, so IP whitelists on
# those servers see the VPN server's own stable IP. Host names resolve on every update.

ALLOW_FILE=$ETC_DIR/allow

# An address has dots and digits only or a colon; anything else must be a host name, so a
# name made of hex letters (bbc.de) resolves instead of reaching nft as is.
IPV4_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
IPV4="^$IPV4_OCTET(\.$IPV4_OCTET){3}(/([0-9]|[12][0-9]|3[0-2]))?$"
IPV6='^[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*(/([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8]))?$'
HOST_LABEL='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
HOST="^($HOST_LABEL\.)*$HOST_LABEL$"

allow_is_address() {
	[[ "$1" =~ $IPV4 || "$1" =~ $IPV6 ]]
}

allow_is_host() {
	[[ "$1" =~ $HOST && ! "$1" =~ ^[0-9.]+$ ]]
}

# allow_check ENTRY...: exit unless every entry is a host, IP or subnet.
allow_check() {
	local entry
	for entry in "$@"; do
		allow_is_address "$entry" || allow_is_host "$entry" || die "Not a host, IP or subnet: $entry"
	done
}

# allow_entries [FILE]: the entries without comments and blanks.
allow_entries() {
	local file="${1:-$ALLOW_FILE}"
	if [ -f "$file" ]; then
		sed -e 's/#.*//' -e 's/[[:space:]]//g' "$file" | awk 'NF'
	fi
}

# allow_resolve: one address per line; host names through getent, invalid entries skipped.
allow_resolve() {
	local entry
	while IFS= read -r entry; do
		if allow_is_address "$entry"; then
			echo "$entry"
		elif allow_is_host "$entry"; then
			getent ahosts "$entry" | awk '{ print $1 }' || echo "cannot resolve $entry" >&2
		else
			echo "skipped, not a host, IP or subnet: $entry" >&2
		fi
	done < <(allow_entries)
}

cmd_allow() {
	local action="$1"
	shift
	need_installed
	case "$action" in
	add) allow_add "$@" ;;
	del) allow_del "$@" ;;
	push) allow_push "$1" ;;
	list)
		allow_print
		return
		;;
	esac
	update_apply >/dev/null
	allow_show
}

allow_add() {
	local entry
	allow_check "$@"
	for entry in "$@"; do
		if allow_entries | grep -qxF "$entry"; then
			echo "already listed: $entry"
		else
			echo "$entry" >>"$ALLOW_FILE"
			echo "added: $entry"
		fi
	done
}

allow_del() {
	local entry
	for entry in "$@"; do
		if allow_entries | grep -qxF "$entry"; then
			echo "removed: $entry"
		else
			echo "not listed: $entry"
		fi
	done
	[ -f "$ALLOW_FILE" ] || return 0
	# Drop the lines whose entry matches; comments and other lines stay.
	awk 'NR == FNR { drop[$0] = 1; next }
		{ entry = $0; sub(/#.*/, "", entry); gsub(/[[:space:]]/, "", entry); if (!(entry in drop)) print }' \
		<(printf '%s\n' "$@") "$ALLOW_FILE" >"$ALLOW_FILE.new"
	mv "$ALLOW_FILE.new" "$ALLOW_FILE"
}

# allow_push FILE: replace the list, printing what changes.
allow_push() {
	local file="$1" entries=()
	[ -f "$file" ] || die "No such file: $file"
	mapfile -t entries < <(allow_entries "$file")
	allow_check ${entries[@]+"${entries[@]}"}
	diff <(allow_entries | sort -u) <(allow_entries "$file" | sort -u) |
		sed -n -e 's/^< /removed: /p' -e 's/^> /added: /p' || true
	install -m 644 "$file" "$ALLOW_FILE"
}

allow_print() {
	if [ -z "$(allow_entries)" ]; then
		echo "Direct list is empty"
	else
		echo "Direct list ($ALLOW_FILE):"
		allow_entries | sed 's/^/  /'
	fi
	allow_show
}

allow_show() {
	if [ -s "$CACHE/allow.resolved" ]; then
		echo "Direct addresses (no geoblock, no WARP):"
		sed 's/^/  /' "$CACHE/allow.resolved"
	else
		echo "No direct addresses"
	fi
}
