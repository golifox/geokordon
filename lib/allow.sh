# shellcheck shell=bash
# Local side of the direct list: the file ALLOW_LIST, edited by `allow add|del` before a sync.

# allow_entries: the entries of ALLOW_LIST without comments and blanks.
allow_entries() {
	if [ -f "$ALLOW_LIST" ]; then
		sed -e 's/#.*//' -e 's/[[:space:]]//g' "$ALLOW_LIST" | awk 'NF'
	fi
}

# allow_check ENTRY...: exit unless every entry looks like a host, IP or subnet.
allow_check() {
	local entry
	for entry in "$@"; do
		[[ "$entry" =~ ^[0-9A-Za-z.:-]+(/[0-9]{1,3})?$ ]] || {
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
