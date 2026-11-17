# shellcheck shell=bash
# warp on|off: route connections opened by the VPN containers through Cloudflare WARP.
# Replies to VPN clients, SSH and the host's own traffic keep the direct route.
# The routing lives in geokordon-warp.service (warp up|down), bound to wg-quick@warp:
# AppArmor forbids wg-quick to run PostUp scripts.

WGCF_VERSION=2.3.1
WARP_DIR=$ETC_DIR/warp
WARP_CONF=/etc/wireguard/warp.conf
WARP_UNIT=$UNIT_DIR/geokordon-warp.service
WARP_SYSCTL=/etc/sysctl.d/90-geokordon-warp.conf
TRACE_URL=https://1.1.1.1/cdn-cgi/trace
MARK=0x2408
TABLE=2408

cmd_warp() {
	case "$1" in
	on)
		need_installed
		warp_on
		;;
	off) warp_off ;;
	up) warp_up ;;
	down) warp_down ;;
	disable) warp_disable ;;
	esac
}

warp_on() {
	need_packages wireguard-tools curl nftables
	command -v docker >/dev/null || die "Docker not found: WARP routes the VPN containers"

	warp_profile
	warp_write_config
	unit_text geokordon-warp.service >"$WARP_UNIT"
	# Replies from WARP arrive on another interface than the default route: loose reverse
	# path. The original values come back with warp off.
	if [ ! -f "$WARP_DIR/rp_filter" ]; then
		sysctl -n net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter >"$WARP_DIR/rp_filter"
	fi
	printf 'net.ipv4.conf.all.rp_filter = 2\nnet.ipv4.conf.default.rp_filter = 2\n' >"$WARP_SYSCTL"
	sysctl -q -p "$WARP_SYSCTL"
	systemctl daemon-reload

	# Safety net: if this run dies midway, WARP switches itself off in 5 minutes.
	warp_cancel_rollback
	systemd-run --quiet --unit geokordon-warp-rollback --on-active=300 "$BIN" warp disable

	systemctl enable wg-quick@warp.service geokordon-warp.service >/dev/null 2>&1
	systemctl restart wg-quick@warp.service
	systemctl restart geokordon-warp.service

	local trace="" container_status=0
	trace="$(warp_host_trace)" || true
	if [[ "$trace" == *warp=on* ]]; then
		warp_container_check || container_status=$?
	fi
	if [[ "$trace" != *warp=on* ]] || [ "$container_status" = 1 ]; then
		warp_off >/dev/null
		die "WARP check failed, traffic goes direct again"
	fi

	warp_cancel_rollback
	echo "WARP on: container traffic leaves through Cloudflare $(sed -n 's/^ip=//p' <<<"$trace")"
	if [ "$container_status" = 2 ]; then
		echo "note: no VPN container has wget or curl, the container route was not checked"
	fi
}

warp_off() {
	local all default
	warp_cancel_rollback
	warp_disable
	rm -f "$WARP_SYSCTL"
	if [ -f "$WARP_DIR/rp_filter" ]; then
		{
			read -r all
			read -r default
		} <"$WARP_DIR/rp_filter"
		sysctl -q -w "net.ipv4.conf.all.rp_filter=$all" "net.ipv4.conf.default.rp_filter=$default"
		rm -f "$WARP_DIR/rp_filter"
	fi
	echo "WARP off: traffic goes direct"
}

# warp_purge: switch WARP off and delete its account, config and unit.
warp_purge() {
	warp_off >/dev/null
	rm -rf "$WARP_DIR"
	rm -f "$WARP_CONF" "$WARP_UNIT"
	systemctl daemon-reload
}

warp_disable() {
	systemctl disable --now geokordon-warp.service wg-quick@warp.service >/dev/null 2>&1 || true
	warp_down
}

warp_cancel_rollback() {
	systemctl stop geokordon-warp-rollback.timer 2>/dev/null || true
	systemctl reset-failed geokordon-warp-rollback.service geokordon-warp-rollback.timer 2>/dev/null || true
}

# warp_subnets: subnets of the Docker networks the VPN containers are attached to.
warp_subnets() {
	local container network
	for container in $(docker ps -a --format '{{.Names}}' | grep -E -- "$CONTAINERS"); do
		docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' "$container"
	done | awk 'NF && $0 != "host" && $0 != "none"' | sort -u | while read -r network; do
		docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' "$network"
	done | awk '/^[0-9.]+\/[0-9]+$/' | sort -u | paste -sd, -
}

# warp_up (geokordon-warp.service start): mark connections opened by the containers, route them to warp.
warp_up() {
	local subnets allowed direct=""
	subnets="$(warp_subnets)"
	# The direct list, resolved by update, stays off WARP: it sees the server's stable IP.
	allowed="$(awk '/^[0-9.]+(\/[0-9]+)?$/' "$CACHE/allow.resolved" 2>/dev/null | paste -sd, - || true)"
	if [ -n "$allowed" ]; then direct="elements = { $allowed }"; fi
	[ -n "$subnets" ] || die "geokordon warp: no Docker networks of VPN containers found"

	nft -f - <<EOF
table ip geokordon_warp
delete table ip geokordon_warp
table ip geokordon_warp {
  set containers { type ipv4_addr; flags interval; elements = { $subnets } }
  set private {
    type ipv4_addr; flags interval
    elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }
  }
  set direct { type ipv4_addr; flags interval; auto-merge; $direct }
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;
    # Only connections the containers open; replies to VPN clients are the reply direction.
    ct direction original ip saddr @containers ip daddr != @private ip daddr != @direct fib daddr type != local meta mark set $MARK
  }
  chain forward {
    type filter hook forward priority mangle; policy accept;
    oifname "warp" tcp flags syn tcp option maxseg size set rt mtu
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "warp" masquerade
  }
}
EOF
	ip route replace default dev warp table "$TABLE"
	ip rule del fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
	ip rule add fwmark "$MARK" lookup "$TABLE" priority "$TABLE"
}

# warp_down (geokordon-warp.service stop): drop the marks and routes.
warp_down() {
	ip rule del fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
	ip route flush table "$TABLE" 2>/dev/null || true
	nft delete table ip geokordon_warp 2>/dev/null || true
}

# warp_profile: register a free WARP account once and keep it for later runs.
warp_profile() {
	mkdir -p "$WARP_DIR"
	chmod 700 "$WARP_DIR"
	if [ -s "$WARP_DIR/wgcf-profile.conf" ]; then
		return
	fi

	local arch sha
	case "$(uname -m)" in
	x86_64) arch=amd64 sha=4fb7a136aa470ece11d17949c7db07b040ec9c604742dc8680bcf1889f85d0c8 ;;
	aarch64) arch=arm64 sha=710ab2d8ac145d81a4cf0c11bdb0e05914f77ae2a45f67b87e718d84b4cb7301 ;;
	*) die "Unsupported CPU for wgcf: $(uname -m)" ;;
	esac
	curl -fsSL --retry 3 -o "$WARP_DIR/wgcf" \
		"https://github.com/ViRb3/wgcf/releases/download/v$WGCF_VERSION/wgcf_${WGCF_VERSION}_linux_$arch"
	echo "$sha  $WARP_DIR/wgcf" | sha256sum -c --quiet -
	chmod 755 "$WARP_DIR/wgcf"
	local log
	log="$(cd "$WARP_DIR" && ./wgcf register --accept-tos 2>&1 && ./wgcf generate 2>&1)" || {
		echo "$log" >&2
		die "WARP registration failed"
	}
}

# warp_write_config: wg-quick config without its own routes; geokordon-warp.service routes only the containers.
warp_write_config() {
	local profile="$WARP_DIR/wgcf-profile.conf" key address peer endpoint
	key="$(sed -n 's/^PrivateKey *= *//p' "$profile")"
	peer="$(sed -n 's/^PublicKey *= *//p' "$profile")"
	endpoint="$(sed -n 's/^Endpoint *= *//p' "$profile")"
	address="$(sed -n 's/^Address *= *//p' "$profile" | tr ',' '\n' | tr -d ' ' |
		awk '/^[0-9.]+\/[0-9]+$/ { print; exit }')"
	if [ -z "$key" ] || [ -z "$peer" ] || [ -z "$endpoint" ] || [ -z "$address" ]; then
		die "Unexpected wgcf profile: $profile"
	fi

	mkdir -p "$(dirname "$WARP_CONF")"
	(
		umask 077
		cat >"$WARP_CONF" <<EOF
[Interface]
PrivateKey = $key
Address = $address
MTU = 1280
Table = off

[Peer]
PublicKey = $peer
AllowedIPs = 0.0.0.0/0
Endpoint = $endpoint
PersistentKeepalive = 25
EOF
	)
}

# warp_host_trace: Cloudflare trace through the WARP interface (contains warp=on when it works).
warp_host_trace() {
	local attempt
	for attempt in 1 2 3 4 5; do
		if curl -fsS -m 10 --interface warp "$TRACE_URL" 2>/dev/null; then
			return 0
		fi
		sleep "$attempt"
	done
	return 1
}

# warp_container_check: 0 when a container's traffic leaves through WARP, 1 when it does not,
# 2 when no VPN container has a tool to check with.
warp_container_check() {
	local container
	for container in $(docker ps --format '{{.Names}}' | grep -E -- "$CONTAINERS"); do
		if docker exec "$container" sh -c 'command -v wget || command -v curl' >/dev/null 2>&1; then
			docker exec "$container" sh -c \
				"wget -qO- -T 10 $TRACE_URL 2>/dev/null || curl -fsS -m 10 $TRACE_URL" 2>/dev/null |
				grep '^warp=on' >/dev/null && return 0
			echo "container $container does not leave through WARP" >&2
			return 1
		fi
	done
	return 2
}
