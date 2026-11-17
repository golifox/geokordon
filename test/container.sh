#!/usr/bin/env bash
# Runs the bats tests as root with nft, as CI does, on Debian/Ubuntu or the RHEL family:
#   docker run --rm --cap-add NET_ADMIN -v "$PWD:/src:ro" debian:12 bash /src/test/container.sh
#   docker run --rm --cap-add NET_ADMIN -v "$PWD:/src:ro" rockylinux:9 bash /src/test/container.sh
set -euo pipefail
if command -v apt-get >/dev/null; then
	apt-get update -qq >/dev/null
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bats nftables gzip >/dev/null
else
	# bats comes from EPEL.
	dnf install -y -q epel-release >/dev/null
	dnf install -y -q bats nftables gzip diffutils procps-ng >/dev/null
fi
cp -R /src /work
bats /work/test
