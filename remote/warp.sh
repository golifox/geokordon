# shellcheck shell=bash
# warp on|off: route connections opened by Amnezia containers through Cloudflare WARP.
# Replies to VPN clients, SSH and the host's own traffic keep the direct route.
# Uses DIR from run.sh.

WGCF_VERSION=2.3.1
WARP_DIR=/etc/ru-block-warp
WARP_CONF=/etc/wireguard/warp.conf
WARP_UNIT=/etc/systemd/system/ru-block-warp.service
WARP_SYSCTL=/etc/sysctl.d/90-ru-block-warp.conf
TRACE_URL=https://1.1.1.1/cdn-cgi/trace

warp_on() {
	need_packages wireguard-tools curl nftables
	command -v docker >/dev/null || {
		echo "Docker not found: WARP routes the Amnezia containers" >&2
		exit 1
	}

	warp_profile
	warp_write_config
	install -m 755 "$DIR/files/ru-block-warp" /usr/local/sbin/ru-block-warp
	install -m 644 "$DIR/files/ru-block-warp.service" "$WARP_UNIT"
	# Replies from WARP arrive on another interface than the default route: loose reverse path.
	printf 'net.ipv4.conf.all.rp_filter = 2\nnet.ipv4.conf.default.rp_filter = 2\n' >"$WARP_SYSCTL"
	sysctl -q -p "$WARP_SYSCTL"
	systemctl daemon-reload

	# Safety net: if this run dies midway, WARP switches itself off in 5 minutes.
	warp_cancel_rollback
	systemd-run --quiet --unit ru-block-warp-rollback --on-active=300 /usr/local/sbin/ru-block-warp disable

	systemctl enable wg-quick@warp.service ru-block-warp.service >/dev/null 2>&1
	systemctl restart wg-quick@warp.service
	systemctl restart ru-block-warp.service

	local trace="" container_status=0
	trace="$(warp_host_trace)" || true
	if [[ "$trace" == *warp=on* ]]; then
		warp_container_check || container_status=$?
	fi
	if [[ "$trace" != *warp=on* ]] || [ "$container_status" = 1 ]; then
		/usr/local/sbin/ru-block-warp disable
		warp_cancel_rollback
		echo "WARP check failed, traffic goes direct again" >&2
		exit 1
	fi

	warp_cancel_rollback
	echo "WARP on: Amnezia traffic leaves through Cloudflare $(sed -n 's/^ip=//p' <<<"$trace")"
	if [ "$container_status" = 2 ]; then
		echo "note: no Amnezia container has wget or curl, the container route was not checked"
	fi
}

warp_off() {
	if [ -x /usr/local/sbin/ru-block-warp ]; then
		/usr/local/sbin/ru-block-warp disable
	fi
	echo "WARP off: traffic goes direct"
}

# warp_purge: switch WARP off and delete its account, config and helpers.
warp_purge() {
	warp_cancel_rollback
	if [ -x /usr/local/sbin/ru-block-warp ]; then
		/usr/local/sbin/ru-block-warp disable
	fi
	rm -rf "$WARP_DIR"
	rm -f "$WARP_CONF" "$WARP_UNIT" "$WARP_SYSCTL" /usr/local/sbin/ru-block-warp
	systemctl daemon-reload
}

warp_cancel_rollback() {
	systemctl stop ru-block-warp-rollback.timer 2>/dev/null || true
	systemctl reset-failed ru-block-warp-rollback.service ru-block-warp-rollback.timer 2>/dev/null || true
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
	*)
		echo "Unsupported CPU for wgcf: $(uname -m)" >&2
		exit 1
		;;
	esac
	curl -fsSL --retry 3 -o "$WARP_DIR/wgcf" \
		"https://github.com/ViRb3/wgcf/releases/download/v$WGCF_VERSION/wgcf_${WGCF_VERSION}_linux_$arch"
	echo "$sha  $WARP_DIR/wgcf" | sha256sum -c --quiet -
	chmod 755 "$WARP_DIR/wgcf"
	local log
	log="$(cd "$WARP_DIR" && ./wgcf register --accept-tos 2>&1 && ./wgcf generate 2>&1)" || {
		echo "$log" >&2
		echo "WARP registration failed" >&2
		exit 1
	}
}

# warp_write_config: wg-quick config without its own routes; ru-block-warp.service routes only Amnezia.
warp_write_config() {
	local profile="$WARP_DIR/wgcf-profile.conf" key address peer endpoint
	key="$(sed -n 's/^PrivateKey *= *//p' "$profile")"
	peer="$(sed -n 's/^PublicKey *= *//p' "$profile")"
	endpoint="$(sed -n 's/^Endpoint *= *//p' "$profile")"
	address="$(sed -n 's/^Address *= *//p' "$profile" | tr ',' '\n' | tr -d ' ' |
		awk '/^[0-9.]+\/[0-9]+$/ { print; exit }')"
	if [ -z "$key" ] || [ -z "$peer" ] || [ -z "$endpoint" ] || [ -z "$address" ]; then
		echo "Unexpected wgcf profile: $profile" >&2
		exit 1
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
# 2 when no Amnezia container has a tool to check with.
warp_container_check() {
	local container
	for container in $(docker ps --format '{{.Names}}' | awk '/^amnezia/'); do
		if docker exec "$container" sh -c 'command -v wget || command -v curl' >/dev/null 2>&1; then
			docker exec "$container" sh -c \
				"wget -qO- -T 10 $TRACE_URL 2>/dev/null || curl -fsS -m 10 $TRACE_URL" 2>/dev/null |
				grep -q '^warp=on' && return 0
			echo "container $container does not leave through WARP" >&2
			return 1
		fi
	done
	return 2
}
