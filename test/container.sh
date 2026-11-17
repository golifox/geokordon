#!/usr/bin/env bash
# Runs the bats tests as root with nft, as CI does:
#   docker run --rm --cap-add NET_ADMIN -v "$PWD:/src:ro" debian:12 bash /src/test/container.sh
set -euo pipefail
apt-get update -qq >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bats nftables gzip >/dev/null
cp -R /src /work
bats /work/test
