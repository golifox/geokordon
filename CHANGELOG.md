# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-17

### Added

- Direct list: hosts, IPs and subnets in a local, git-ignored `allow.list` skip both the geoblock and WARP, for servers in Russia and for IP whitelists that expect the server's own IP. `./ru-block allow add|del` edit the file and sync, `allow sync` and `install` send it, `allow list` shows the server's list with resolved addresses; host names resolve on the server on every refresh.

## [0.1.0] - 2026-11-17

### Added

- `./ru-block install`: nftables geoblock for Amnezia exit servers. Inbound from Russian ranges reaches only SSH and the Amnezia ports; forwarded connections to Russian destinations are rejected (TCP with a reset, so clients fail at once). Ranges from ipdeny.com refresh on boot and daily.
- `./ru-block warp on|off`: connections opened by Amnezia containers leave through Cloudflare WARP (wgcf account, `wg-quick@warp`), with a self-check and automatic rollback.
- `./ru-block remove`: removes the geoblock and WARP.
- Interactive login: server IP, SSH port (default 22), user (default root), password or SSH key; non-root users run through sudo, with fix hints when key login or passwordless sudo fails.

[Unreleased]: https://github.com/golifox/amnezia-ru-block/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/golifox/amnezia-ru-block/releases/tag/v0.2.0
[0.1.0]: https://github.com/golifox/amnezia-ru-block/releases/tag/v0.1.0
