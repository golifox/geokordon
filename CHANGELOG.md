# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `geokordon config countries ru,by`: block any countries ipdeny.com lists, not only Russia.
- `geokordon config containers '^(amnezia|3x-ui)'`: the VPN containers by a name pattern, so 3x-ui, Marzban, plain WireGuard and others get their ports opened and their traffic routed through WARP.
- `config` without arguments shows the settings. A setting is checked, saved to `/etc/geokordon/config` and applied at once; if applying fails, it goes back as it was.
- `gk`, the short name: `install` links `/usr/local/sbin/gk` to `geokordon` unless the name is taken, `remove` drops it. Run from a checkout, `geokordon` also works through a symlink, so `ln -s "$PWD/geokordon" ~/.local/bin/gk` gives the same on your machine.
- The RHEL family: packages through dnf on Rocky, Alma, RHEL and Fedora. CI runs the tests on Rocky 9 too, and a full install–config–remove run with systemd and firewalld.

### Changed

- The nft sets are `geo4`/`geo6` instead of `ru4`/`ru6`; `status` shows the blocked countries and the container pattern.
- The download check no longer needs 1000 IPv4 / 200 IPv6 prefixes, which small countries never reach: every line must be a prefix, there must be at least half as many as cached, and at least 10 IPv4 prefixes on a country's first download.
- Descriptions speak of a VPN server in Docker; Amnezia stays the default.
- Range downloads retry on every error over HTTP/1.1: ipdeny.com drops TLS connections and HTTP/2 streams now and then, and plain `--retry` let a single drop fail the update.
- `config containers` refuses a pattern that matches none of the containers, and a hand-edited setting that would not pass the check falls back to the default with a warning, so a typo cannot close the VPN ports or empty the geoblock. A WARP refresh failure after the rules are applied only warns.

## [0.5.0] - 2026-11-17

### Added

- Several targets: repeat `-H` (or list them in `GEOKORDON_HOST`, separated by spaces) to run a command on each server in turn, with a header per server; a failure on one does not stop the rest, and the exit code reports it.
- `allow pull`: print a server's direct list in the format `allow push` takes. It reads the file over plain ssh, without sudo, so the output can go straight into a file.

## [0.4.0] - 2026-11-17

### Added

- `geokordon` lives on the server in `/usr/local/sbin` and does everything there: `sudo geokordon warp on` works without your machine.
- `install.sh` in each release: `curl -fsSL …/releases/latest/download/install.sh | sudo bash`, checked against `SHA256SUMS`.
- `-H TARGET` (or `GEOKORDON_HOST`) and `-p PORT`: the target goes to ssh as is, so aliases from `~/.ssh/config` work. The front runs its own copy over one ssh connection, so each password is asked once and nothing stays behind; a non-root user goes through `sudo`.
- `update`, `status`, `allow push FILE`, `--help`, `--version`.
- CI: shellcheck, shfmt, bats (with `nft -c` on generated rules), and an install–status–remove run on Ubuntu 22.04 and 24.04. Releases are built from a `v*` tag.

### Changed

- The direct list lives only on the server, in `/etc/geokordon/allow`: `allow add|del` edit it there, `install` leaves it alone, `remove` prints it before deleting. The local `allow.list`, `allow sync` and `GEOKORDON_ALLOW` are gone.
- Without arguments `geokordon` prints its usage instead of running `install`.
- Without a target it asks one question, the server; the SSH port, user and password prompts are gone, and so are the `SSH_ASKPASS` helper and the OpenSSH 8.4+ requirement.
- State moved to `/etc/geokordon/` (`allow`, `ports`, `warp/`); the helpers `geokordon-update` and `geokordon-warp` became `geokordon update` and `geokordon warp up|down`.

### Fixed

- Open ports no longer pile up: they are found again on every update, and a removed container's ports close. `/etc/geokordon/ports` holds only the ports kept open by hand. Port ranges and stopped containers are covered.
- `warp off` restores the original `rp_filter`.
- The timer and a manual run can no longer collide.

### Upgrade

Run `geokordon -H root@host install` (or the `install.sh` line on the server): it moves `/etc/geokordon.allow`, `/etc/geokordon.ports` and `/etc/geokordon-warp` into `/etc/geokordon/` and removes the old helpers. WARP stays as it was. The old ports file becomes the hand-kept list, so drop ports there that no longer need to stay open. A server switched to WARP by 0.3.x has no saved `rp_filter`, so `warp off` leaves it at 2 there.

## [0.3.1] - 2026-11-17

### Fixed

- After a reboot the server stayed without the geoblock until `geokordon.timer` fired, up to an hour later. `geokordon-restore.service` now loads the cached rules before the network is up. Run `./geokordon install` to add it to a server.
- Host names made of hex letters (`bbc.de`, `fb.ee`) in the direct list were taken for addresses and broke the refresh. Addresses and host names now follow the same strict rules locally and on the server, the server skips invalid entries, and generated rules pass `nft -c` before they replace the current ones.
- A truncated or altered ipdeny.com answer could narrow the block silently. A download replaces the cached list only when every line is a prefix and there are at least 1000 IPv4 / 200 IPv6 prefixes and half of the cached count.

## [0.3.0] - 2026-11-17

### Added

- `./geokordon install --with-warp | --without-warp`: install or update the geoblock and switch WARP on or off in the same run. Without a flag WARP stays as it is.

### Changed

- Renamed from `amnezia-ru-block` to `geokordon`: the command, the server helpers and units (`geokordon-update`, `geokordon-warp`, `geokordon.timer`), the nftables tables (`inet geokordon`, `ip geokordon_warp`), the files under `/etc` and `/var/lib`, and the `GEOKORDON_ALLOW` variable. A server set up by 0.2.0 keeps the old names: run `./ru-block remove` from 0.2.0 before installing this version.

## [0.2.0] - 2026-11-17

### Added

- Direct list: hosts, IPs and subnets in a local, git-ignored `allow.list` skip both the geoblock and WARP, for servers in Russia and for IP whitelists that expect the server's own IP. `./ru-block allow add|del` edit the file and sync, `allow sync` and `install` send it, `allow list` shows the server's list with resolved addresses; host names resolve on the server on every refresh.

## [0.1.0] - 2026-11-17

### Added

- `./ru-block install`: nftables geoblock for Amnezia exit servers. Inbound from Russian ranges reaches only SSH and the Amnezia ports; forwarded connections to Russian destinations are rejected (TCP with a reset, so clients fail at once). Ranges from ipdeny.com refresh on boot and daily.
- `./ru-block warp on|off`: connections opened by Amnezia containers leave through Cloudflare WARP (wgcf account, `wg-quick@warp`), with a self-check and automatic rollback.
- `./ru-block remove`: removes the geoblock and WARP.
- Interactive login: server IP, SSH port (default 22), user (default root), password or SSH key; non-root users run through sudo, with fix hints when key login or passwordless sudo fails.

[Unreleased]: https://github.com/golifox/geokordon/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/golifox/geokordon/releases/tag/v0.5.0
[0.4.0]: https://github.com/golifox/geokordon/releases/tag/v0.4.0
[0.3.1]: https://github.com/golifox/geokordon/releases/tag/v0.3.1
[0.3.0]: https://github.com/golifox/geokordon/releases/tag/v0.3.0
[0.2.0]: https://github.com/golifox/geokordon/releases/tag/v0.2.0
[0.1.0]: https://github.com/golifox/geokordon/releases/tag/v0.1.0
