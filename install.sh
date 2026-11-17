#!/usr/bin/env bash
# Install geokordon on this server from a GitHub release and run geokordon install.
#   curl -fsSL https://github.com/golifox/geokordon/releases/latest/download/install.sh | sudo bash -s -- [--with-warp | --without-warp]
# The copy attached to a release installs that release: the release workflow sets VERSION.
set -euo pipefail

REPO=golifox/geokordon
VERSION=latest

[ "$(id -u)" = 0 ] || {
	echo "Needs root: pipe to sudo bash" >&2
	exit 1
}
if [ "$VERSION" = latest ]; then
	base="https://github.com/$REPO/releases/latest/download"
else
	base="https://github.com/$REPO/releases/download/$VERSION"
fi

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
curl -fsSL --retry 3 -o "$dir/geokordon" "$base/geokordon"
curl -fsSL --retry 3 -o "$dir/SHA256SUMS" "$base/SHA256SUMS"
(cd "$dir" && grep ' geokordon$' SHA256SUMS | sha256sum -c --quiet -)
bash "$dir/geokordon" install "$@"
