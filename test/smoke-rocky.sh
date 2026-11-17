#!/usr/bin/env bash
# Smoke run on Rocky 9 with systemd in Docker: install, status, config, allow, firewalld
# reload, boot restore, remove. Needs Docker with privileged containers; CI runs it too.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME=geokordon-smoke-rocky
"$ROOT/scripts/build" >/dev/null

docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null' EXIT
docker run -d --name "$NAME" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
	-v "$ROOT/dist:/dist:ro" rockylinux:9 \
	bash -c 'dnf install -y -q systemd procps-ng iproute >/dev/null && exec /usr/sbin/init' >/dev/null

x() { docker exec "$NAME" "$@"; }
step() { echo "=== $*"; }

# is-system-running exits non-zero on degraded, so the state is read, not piped.
for _ in $(seq 90); do
	state="$(x systemctl is-system-running 2>/dev/null || true)"
	if [[ "$state" =~ ^(running|degraded)$ ]]; then break; fi
	sleep 2
done

step install
x bash /dist/geokordon install
x geokordon status | tee /dev/stderr | grep >/dev/null 'Geoblock: on'
x systemctl is-enabled geokordon-restore.service geokordon.timer

step "config countries ru,by"
x geokordon config countries ru,by
x geokordon status | grep >/dev/null 'Blocked countries: ru,by'
x test -s /var/lib/geokordon/by4.zone
step "a bad country leaves the config as it was"
if x geokordon config countries ru,xx; then exit 1; fi
x gk config | grep -x 'countries=ru,by' >/dev/null

step "allow add"
x geokordon allow add 1.1.1.1
x nft list set inet geokordon allow4 | grep >/dev/null 1.1.1.1

step "firewalld reload keeps the table"
if x dnf install -y -q firewalld >/dev/null && x systemctl start firewalld; then
	x firewall-cmd -q --reload
	x nft list table inet geokordon >/dev/null
	x systemctl stop firewalld
else
	echo "firewalld did not start here, skipped"
fi

step "boot restore"
x nft delete table inet geokordon
x systemctl restart geokordon-restore.service
x nft list table inet geokordon >/dev/null

step remove
x geokordon remove
if x nft list table inet geokordon >/dev/null 2>&1; then exit 1; fi
x test ! -e /usr/local/sbin/geokordon
x test ! -e /usr/local/sbin/gk
echo "smoke on Rocky 9: ok"
