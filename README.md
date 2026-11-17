# amnezia-ru-block

Closes an Amnezia VPN exit server to Russian IP ranges with one command from your machine, and optionally sends its traffic out through Cloudflare WARP.

- **Outbound:** VPN clients cannot reach Russian destinations through the server, so Russian services never see its IP.
- **Inbound:** Russian addresses reach only SSH and the Amnezia ports; clients in Russia connect as usual.
- **WARP (optional):** connections opened by the Amnezia containers (AWG, XRay and the rest) leave through Cloudflare, so sites see a Cloudflare IP instead of the server's.

## Usage

```bash
./ru-block             # install or update the geoblock
./ru-block warp on     # route Amnezia traffic through WARP
./ru-block warp off    # back to direct
./ru-block remove      # remove everything, WARP included
```

It asks for the server IP, SSH port (default `22`), user (default `root`) and password. An empty password uses SSH keys; a non-root user then needs passwordless `sudo`.

Requirements: Debian or Ubuntu with Amnezia in Docker on the server; `bash`, `tar` and OpenSSH 8.4+ locally (macOS, Linux, or Git Bash on Windows).

## On the server

- nftables table `inet ru_block`; the rest of the firewall and Docker rules stay untouched.
- Ranges from [ipdeny.com](https://www.ipdeny.com), refreshed on boot and daily by `ru-block.timer`.
- Open ports are detected from `sshd` and `amnezia-*` containers and kept in `/etc/ru-block.ports`. Add a missing one with `echo "udp 51820" >> /etc/ru-block.ports && ru-block-update`.
- WARP: a free account made by [wgcf](https://github.com/ViRb3/wgcf), interface `wg-quick@warp`, routing in `ru-block-warp.service`. Replies to VPN clients, SSH and the server's own traffic keep the direct route. `warp on` checks the route from the host and from a container and switches back if either fails.

## Notes

- Russian sites will not open through the VPN: enable split tunneling on clients.
- In a cascade, run it on the exit nodes.

## Layout

| Path | Role |
| --- | --- |
| `ru-block` | entry point: arguments and command dispatch |
| `lib/ssh.sh` | prompts, password or key login, upload and run as root |
| `remote/` | copied to the server per run: `run.sh` dispatches to `install.sh`, `warp.sh`, `remove.sh` |
| `remote/files/` | installed on the server: refresh and WARP helpers, systemd units |

`mise run lint` runs shellcheck over every script.
