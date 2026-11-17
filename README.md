# geokordon

Closes a VPN exit server in Docker to the IP ranges of chosen countries (Russia by default), and optionally sends the containers' traffic out through Cloudflare WARP. Works with Amnezia, 3x-ui, Marzban, plain WireGuard and other VPN servers in Docker.

- **Outbound:** VPN clients cannot reach the blocked countries through the server, so their services never see its IP.
- **Inbound:** addresses in those countries reach only SSH and the VPN ports; clients there connect as usual.
- **WARP (optional):** connections opened by the VPN containers leave through Cloudflare, so sites see a Cloudflare IP instead of the server's.
- **Direct list:** chosen addresses skip both the geoblock and WARP, for servers in the blocked countries you need and for IP whitelists that expect the server's own IP.

## Install

One file, `geokordon`, is both the server program and the front. Pick one way:

```bash
# On the server
curl -fsSL https://github.com/golifox/geokordon/releases/latest/download/install.sh | sudo bash -s -- --with-warp

# The same with a pinned release
curl -fsSL https://github.com/golifox/geokordon/releases/download/v0.6.0/install.sh | sudo bash

# From your machine (macOS, Linux, Git Bash or WSL on Windows): a release file or this repository
geokordon -H root@203.0.113.5 install --with-warp
```

`install.sh` checks the download against `SHA256SUMS` of the release. Without `--with-warp` or `--without-warp`, WARP stays as it is, so a rerun only updates.

Requirements: systemd, nftables and the VPN in Docker on the server — Debian, Ubuntu, Rocky, Alma, RHEL or Fedora (packages come through apt or dnf); `bash` and `ssh` on your machine.

## Usage

```bash
geokordon install [--with-warp | --without-warp]
geokordon update                 # download the ranges and apply the rules now
geokordon status                 # what is installed and applied
geokordon config                 # the settings
geokordon config countries ru,by # blocked countries, ipdeny codes (default ru)
geokordon config containers '^(amnezia|3x-ui)'  # VPN container names (default ^amnezia)
geokordon warp on | warp off
geokordon allow add example.ru 203.0.113.10
geokordon allow del 203.0.113.10
geokordon allow list             # the direct list and what it resolved to
geokordon allow push servers.txt # replace the direct list with a file
geokordon allow pull             # print the direct list in the format allow push takes
geokordon remove                 # everything, WARP and this program included
```

On the server run them with `sudo`. From another machine add `-H TARGET` (or set `GEOKORDON_HOST`): `user@host` or any alias from `~/.ssh/config`, with `-p PORT` for another ssh port. Repeat `-H` (or list targets in `GEOKORDON_HOST`, separated by spaces) to run the command on each server in turn; a failure on one does not stop the rest. The front runs its own copy on the server over one ssh connection; a non-root user goes through `sudo`, which asks for its password when ssh has a terminal, and needs passwordless `sudo` otherwise. Every command but `status`, `config` without arguments, `allow list|pull` and `remove` also updates the installed copy to the front's version. Not on Linux and without a target, it asks for one.

`config countries` and `config containers` check the value, save it to `/etc/geokordon/config` and apply the rules at once; if that fails (an unknown country, say), the setting goes back as it was. The container pattern is an extended regular expression on container names: their published ports stay open, and WARP routes their traffic.

One direct list for several servers: take it from one, edit, push to all.

```bash
geokordon -H root@vpn1 allow pull >~/.config/geokordon/allow.list
geokordon -H root@vpn1 -H root@vpn2 allow push ~/.config/geokordon/allow.list
```

## On the server

- `/usr/local/sbin/geokordon`, units `geokordon.timer`, `geokordon-restore.service`, `geokordon-warp.service`; nftables table `inet geokordon` with the sets `geo4`/`geo6`. The rest of the firewall, firewalld and Docker rules stay untouched.
- Ranges from [ipdeny.com](https://www.ipdeny.com) for each blocked country, refreshed after boot and daily. A download replaces the cached list only when every line is a prefix and there are at least half as many as cached (and at least 10 IPv4 prefixes on the first download); generated rules pass `nft -c` before they replace the current ones.
- On boot `geokordon-restore.service` loads the last applied rules from `/var/lib/geokordon/geokordon.nft` before the network is up, without downloading anything.
- Open ports are found on every update: SSH from `sshd` and `ssh.socket`, and the published ports of the VPN containers, stopped ones and port ranges included. A port of a removed container closes. Ports to keep open by hand go to `/etc/geokordon/ports` (`udp 51820`, one per line), then `sudo geokordon update`.
- Direct list in `/etc/geokordon/allow`: the server is the only copy, `remove` prints it before deleting. Host names resolve on every update; hosts behind a CDN change IPs often, so prefer their subnets.
- WARP: a free account made by [wgcf](https://github.com/ViRb3/wgcf) in `/etc/geokordon/warp`, interface `wg-quick@warp`. Replies to VPN clients, SSH and the server's own traffic keep the direct route. `warp on` checks the route from the host and from a container and switches back if either fails; `warp off` restores the original `rp_filter`.
- Changing commands take a lock, so the timer and a manual run never overlap.

## Notes

- Sites in the blocked countries will not open through the VPN: enable split tunneling on clients, or add them to the direct list.
- Blocking the country you administer from leaves you SSH and the VPN ports only.
- In a cascade, run it on the exit nodes.

## Layout

| Path | Role |
| --- | --- |
| `geokordon` | entry point: arguments, front or local run |
| `lib/` | modules: `common`, `config`, `allow`, `update`, `warp`, `install`, `status`, `remove`, `front` |
| `units/` | systemd units, embedded by the build |
| `scripts/build` | `dist/geokordon`: modules and units in one file |
| `install.sh` | installer for `curl … \| sudo bash` |
| `test/` | bats tests; `container.sh` runs them as root with nft on Debian or Rocky; `smoke-rocky.sh` is a full run on Rocky 9 with systemd |

`mise run lint`, `mise run test`, `mise run build`. Releases are built by GitHub Actions from a `v*` tag. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
