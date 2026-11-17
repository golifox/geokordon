# shellcheck shell=bash
# update: rebuild the nftables table geokordon. Sources in the blocked countries reach only
# SSH and the container ports; forwarded connections to them are rejected.

PORTS_FILE=$ETC_DIR/ports
NFT_FILE=$CACHE/geokordon.nft
V4_ZONES=https://www.ipdeny.com/ipblocks/data/aggregated
V6_ZONES=https://www.ipdeny.com/ipv6/ipaddresses/aggregated
V4_PREFIX='^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$'
V6_PREFIX='^[0-9a-f:]+/[0-9]{1,3}$'

# prefix_count FILE REGEX: the number of lines, or nothing when a non-empty line does not match.
# grep, not awk: Debian's mawk has no {n,m} intervals.
# Counting, not grep -q: an early exit under pipefail reads as a failure.
prefix_count() {
	local bad
	bad="$(grep -v '^$' "$1" | grep -cvE "$2" || true)"
	if [ "$bad" = 0 ]; then
		grep -cE "$2" "$1" || true
	fi
}

# prefix_fetch URL FILE REGEX MIN: replace FILE with the download only when every line is a
# prefix and there are at least MIN of them and at least half of the cached count: a
# truncated or altered answer must not narrow the block silently.
prefix_fetch() {
	local url="$1" file="$2" re="$3" min="$4" count old=0
	# ipdeny.com drops connections now and then (TLS EOF, broken HTTP/2 streams), which plain
	# --retry does not cover: retry on every error, over HTTP/1.1.
	if ! curl -fsS --http1.1 --retry 5 --retry-all-errors --retry-delay 5 -m 120 "$url" -o "$file.new"; then
		rm -f "$file.new"
		echo "download failed: $url (using cached list if any)" >&2
		return 0
	fi
	count="$(prefix_count "$file.new" "$re")"
	if [ -f "$file" ]; then old="$(prefix_count "$file" "$re")"; fi
	if [ -n "$count" ] && [ "$count" -ge "$min" ] && [ $((count * 2)) -ge "${old:-0}" ]; then
		mv "$file.new" "$file"
	else
		rm -f "$file.new"
		echo "rejected $url: ${count:-malformed} prefixes, need $min and half of the cached ${old:-0} (using cached list if any)" >&2
	fi
}

# ports_from_bindings: "51820/udp 51820" lines of docker inspect to "udp 51820".
ports_from_bindings() {
	awk '$2 ~ /^[0-9]+$/ { split($1, a, "/"); print a[2] " " $2 }'
}

# ports_detect: SSH ports and the published ports of the VPN containers, recounted on every
# update. PortBindings covers stopped containers too, and Docker lists a range port by port.
ports_detect() {
	local container names
	sshd -T 2>/dev/null | awk '$1 == "port" { print "tcp " $2 }' || true
	ss -Htlnp 2>/dev/null | awk '/"sshd"/ { n = split($4, a, ":"); print "tcp " a[n] }' || true
	systemctl show -p Listen --value ssh.socket 2>/dev/null |
		grep -oE ':[0-9]+ \(Stream\)' | sed -E 's/^:([0-9]+).*/tcp \1/' || true
	if command -v docker >/dev/null; then
		# A silent Docker (still starting, restarting) would close the VPN ports: fail instead,
		# the current rules stay.
		names="$(docker ps -a --format '{{.Names}}')" || die "Docker does not answer, rules left as they are"
		for container in $names; do
			[[ "$container" =~ $CONTAINERS ]] || continue
			docker inspect -f '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{$p}} {{.HostPort}}{{"\n"}}{{end}}{{end}}' \
				"$container" 2>/dev/null || true # removed after the listing
		done | ports_from_bindings
	fi
}

# ports_all: the ports open for blocked sources, from ports_detect and PORTS_FILE.
ports_all() {
	{
		sed 's/#.*//' "$PORTS_FILE" 2>/dev/null || true
		ports_detect
	} | awk '($1 == "tcp" || $1 == "udp") && NF == 2 && $2 ~ /^[0-9]+$/ && $2 > 0 && $2 < 65536 { print $1, $2 + 0 }' |
		sort -u -k1,1 -k2,2n
}

# rules_generate: the nft script from v4, v6, allow4, allow6, tcp and udp (comma-separated).
rules_generate() {
	echo "table inet geokordon"
	echo "delete table inet geokordon"
	echo "table inet geokordon {"
	echo "  set geo4 { type ipv4_addr; flags interval; auto-merge; elements = { $v4 } }"
	if [ -n "$v6" ]; then
		echo "  set geo6 { type ipv6_addr; flags interval; auto-merge; elements = { $v6 } }"
	fi
	if [ -n "$allow4" ]; then
		echo "  set allow4 { type ipv4_addr; flags interval; auto-merge; elements = { $allow4 } }"
	fi
	if [ -n "$allow6" ]; then
		echo "  set allow6 { type ipv6_addr; flags interval; auto-merge; elements = { $allow6 } }"
	fi
	echo "  chain prerouting {"
	# Before Docker DNAT, so published container ports are covered too.
	echo "    type filter hook prerouting priority -150; policy accept;"
	echo "    ct state established,related accept"
	echo "    iifname \"lo\" accept"
	if [ -n "$allow4" ]; then echo "    ip saddr @allow4 accept"; fi
	if [ -n "$allow6" ]; then echo "    ip6 saddr @allow6 accept"; fi
	if [ -n "$tcp" ]; then echo "    tcp dport { $tcp } accept"; fi
	if [ -n "$udp" ]; then echo "    udp dport { $udp } accept"; fi
	echo "    ip saddr @geo4 drop"
	if [ -n "$v6" ]; then echo "    ip6 saddr @geo6 drop"; fi
	echo "  }"
	echo "  chain forward {"
	# VPN clients must not reach the blocked countries through this server.
	# Only connections initiated towards them; replies to clients there stay allowed.
	# TCP gets a reset: macOS and other BSD stacks ignore ICMP unreachable while connecting
	# and would hang until timeout.
	echo "    type filter hook forward priority -10; policy accept;"
	if [ -n "$allow4" ]; then echo "    ip daddr @allow4 accept"; fi
	if [ -n "$allow6" ]; then echo "    ip6 daddr @allow6 accept"; fi
	echo "    ct direction original ip daddr @geo4 meta l4proto tcp reject with tcp reset"
	echo "    ct direction original ip daddr @geo4 reject"
	if [ -n "$v6" ]; then
		echo "    ct direction original ip6 daddr @geo6 meta l4proto tcp reject with tcp reset"
		echo "    ct direction original ip6 daddr @geo6 reject"
	fi
	echo "  }"
	echo "}"
}

cmd_update() {
	need_installed
	update_apply
}

# update_apply: download, generate, check with nft -c, then replace the cache and the table.
# geokordon-restore.service loads the cached file on boot, so only a checked one lands there.
update_apply() {
	local v4 v6 allow4 allow6 tcp udp cc zones4=() zones6=()
	mkdir -p "$CACHE"
	# The first download of a country needs a few prefixes; later ones at least half the cache.
	for cc in ${COUNTRIES//,/ }; do
		prefix_fetch "$V4_ZONES/$cc-aggregated.zone" "$CACHE/${cc}4.zone" "$V4_PREFIX" 10
		prefix_fetch "$V6_ZONES/$cc-aggregated.zone" "$CACHE/${cc}6.zone" "$V6_PREFIX" 1
		[ -s "$CACHE/${cc}4.zone" ] || die "no IPv4 list for $cc, nothing applied"
		zones4+=("$CACHE/${cc}4.zone")
		if [ -s "$CACHE/${cc}6.zone" ]; then zones6+=("$CACHE/${cc}6.zone"); fi
	done
	[ ${#zones4[@]} -gt 0 ] || die "no countries to block, nothing applied"
	v4="$(awk 'NF' "${zones4[@]}" | paste -sd, -)"
	v6=""
	if [ ${#zones6[@]} -gt 0 ]; then v6="$(awk 'NF' "${zones6[@]}" | paste -sd, -)"; fi

	allow_resolve | sort -u >"$CACHE/allow.resolved.new"
	allow4="$(awk '/^[0-9.]+(\/[0-9]+)?$/' "$CACHE/allow.resolved.new" | paste -sd, -)"
	allow6="$(awk '/:/' "$CACHE/allow.resolved.new" | paste -sd, -)"

	ports_all >"$CACHE/ports.new"
	tcp="$(awk '$1 == "tcp" { print $2 }' "$CACHE/ports.new" | paste -sd, -)"
	udp="$(awk '$1 == "udp" { print $2 }' "$CACHE/ports.new" | paste -sd, -)"

	rules_generate >"$NFT_FILE.new"
	nft -c -f "$NFT_FILE.new" || {
		rm -f "$NFT_FILE.new" "$CACHE/allow.resolved.new" "$CACHE/ports.new"
		die "generated rules rejected by nft, the current ones stay"
	}
	mv "$NFT_FILE.new" "$NFT_FILE"
	mv "$CACHE/allow.resolved.new" "$CACHE/allow.resolved"
	mv "$CACHE/ports.new" "$CACHE/ports"
	nft -f "$NFT_FILE"
	# WARP keeps the direct list out of its marks; rebuild it with the fresh addresses. The
	# geoblock is applied by now, so a WARP failure only warns: failing here would roll back
	# a config or direct list the table already carries. A process of its own, as set -e does
	# not hold inside `||`.
	if systemctl is-active --quiet geokordon-warp.service; then
		bash "$GEOKORDON_SELF" warp up || echo "warning: WARP routing not refreshed, see geokordon warp on" >&2
	fi
	echo "geokordon applied: blocked $COUNTRIES, open to them tcp {$tcp} udp {$udp}"
}
