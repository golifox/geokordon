# shellcheck shell=bash
# Local side of the direct list: the file ALLOW_LIST, edited by `allow add|del` before a sync.

# allow_entries: the entries of ALLOW_LIST without comments and blanks.
allow_entries() {
	if [ -f "$ALLOW_LIST" ]; then
		sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOW_LIST" | awk 'NF'
	fi
}

# Same rules as resolve_allow in remote/files/geokordon-update: an address has dots and
# digits only or a colon; anything else must be a host name.
IPV4_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
IPV4="^$IPV4_OCTET(\.$IPV4_OCTET){3}(/([0-9]|[12][0-9]|3[0-2]))?$"
IPV6='^[0-9A-Fa-f.]*:[0-9A-Fa-f:.]*(/([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8]))?$'
HOST_LABEL='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
HOST="^($HOST_LABEL\.)*$HOST_LABEL$"

# allow_check ENTRY...: exit unless every entry is a host, IP or subnet.
allow_check() {
	local entry
	for entry in "$@"; do
		[[ "$entry" =~ $IPV4 || "$entry" =~ $IPV6 || ("$entry" =~ $HOST && ! "$entry" =~ ^[0-9.]+$) ]] || {
			echo "Not a host, IP or subnet: $entry" >&2
			exit 1
		}
	done
}

allow_local_add() {
	local entry
	if [ ! -f "$ALLOW_LIST" ]; then
		cp "$ROOT/allow.list.example" "$ALLOW_LIST"
	fi
	for entry in "$@"; do
		if allow_entries | grep -qxF "$entry"; then
			echo "already listed: $entry"
		else
			echo "$entry" >>"$ALLOW_LIST"
			echo "added: $entry"
		fi
	done
}

allow_local_del() {
	local entry
	[ -f "$ALLOW_LIST" ] || {
		echo "No $ALLOW_LIST" >&2
		exit 1
	}
	for entry in "$@"; do
		if allow_entries | grep -qxF "$entry"; then
			echo "removed: $entry"
		else
			echo "not listed: $entry"
		fi
	done
	# Drop the lines whose entry matches; comments and other lines stay.
	awk 'NR == FNR { drop[$0] = 1; next }
		{ entry = $0; sub(/#.*/, "", entry); gsub(/[[:space:]]/, "", entry); if (!(entry in drop)) print }' \
		<(printf '%s\n' "$@") "$ALLOW_LIST" >"$ALLOW_LIST.new"
	mv "$ALLOW_LIST.new" "$ALLOW_LIST"
}
