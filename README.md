# geokordon

Closes an Amnezia VPN exit server to Russian IP ranges with one command from your machine, and optionally sends its traffic out through Cloudflare WARP.

- **Outbound:** VPN clients cannot reach Russian destinations through the server, so Russian services never see its IP.
- **Inbound:** Russian addresses reach only SSH and the Amnezia ports; clients in Russia connect as usual.
- **WARP (optional):** connections opened by the Amnezia containers (AWG, XRay and the rest) leave through Cloudflare, so sites see a Cloudflare IP instead of the server's.
- **Direct list:** chosen addresses skip both the geoblock and WARP, for servers in Russia you need and for IP whitelists that expect the server's own IP.

## Usage

```bash
./geokordon             # install or update the geoblock; WARP stays as it is
./geokordon install --with-warp      # the same, then route Amnezia traffic through WARP
./geokordon install --without-warp   # the same, then switch WARP off
./geokordon warp on     # route Amnezia traffic through WARP
./geokordon warp off    # back to direct
./geokordon allow add example.ru 203.0.113.10   # add to allow.list, then sync
./geokordon allow del 203.0.113.10              # remove from allow.list, then sync
./geokordon allow sync  # send allow.list to the server
./geokordon allow list  # the direct list on the server, with resolved addresses
./geokordon remove      # remove everything, WARP included
```

It asks for the server IP, SSH port (default `22`), user (default `root`) and password. An empty password uses SSH keys; a non-root user then needs passwordless `sudo`.

Direct list: the local, git-ignored `allow.list` (one host, IP or subnet per line; `GEOKORDON_ALLOW` points to another path) is the source of truth. `allow add|del` edit it, `install` and `allow sync` replace the server's list with it; without the file `install` leaves the server's list as is.

Requirements: Debian or Ubuntu with Amnezia in Docker on the server; `bash`, `tar` and OpenSSH 8.4+ locally (macOS, Linux, or Git Bash on Windows).

## On the server

- nftables table `inet geokordon`; the rest of the firewall and Docker rules stay untouched.
- Ranges from [ipdeny.com](https://www.ipdeny.com), refreshed on boot and daily by `geokordon.timer`.
- Open ports are detected from `sshd` and `amnezia-*` containers and kept in `/etc/geokordon.ports`. Add a missing one with `echo "udp 51820" >> /etc/geokordon.ports && geokordon-update`.
- WARP: a free account made by [wgcf](https://github.com/ViRb3/wgcf), interface `wg-quick@warp`, routing in `geokordon-warp.service`. Replies to VPN clients, SSH and the server's own traffic keep the direct route. `warp on` checks the route from the host and from a container and switches back if either fails.
- Direct list in `/etc/geokordon.allow`; host names resolve on every refresh, so a changed IP is picked up within a day (or at once with `./geokordon allow sync`). Hosts behind a CDN change IPs often: prefer their subnets.

## Notes

- Russian sites will not open through the VPN: enable split tunneling on clients.
- In a cascade, run it on the exit nodes.

## Layout

| Path | Role |
| --- | --- |
| `geokordon` | entry point: arguments and command dispatch |
| `lib/ssh.sh` | prompts, password or key login, upload and run as root |
| `lib/allow.sh` | local `allow.list`: entries, validation, add and del |
| `remote/` | copied to the server per run: `run.sh` dispatches to `install.sh`, `warp.sh`, `allow.sh`, `remove.sh` |
| `remote/files/` | installed on the server: refresh and WARP helpers, systemd units |

`mise run lint` runs shellcheck over every script. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
