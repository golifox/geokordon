# amnezia-ru-block

Closes an Amnezia VPN exit server to Russian IP ranges with one command from your machine.

- **Outbound:** VPN clients cannot reach Russian destinations through the server, so Russian services never see its IP.
- **Inbound:** Russian addresses reach only SSH and the Amnezia ports; clients in Russia connect as usual.

## Usage

```bash
./ru-block           # install or update
./ru-block remove    # remove everything
```

It asks for the server IP, SSH port (default `22`), user (default `root`) and password. An empty password uses SSH keys; a non-root user then needs passwordless `sudo`.

Requirements: Debian or Ubuntu with Amnezia in Docker on the server; `bash` and OpenSSH 8.4+ locally.

## On the server

- nftables table `inet ru_block`; the rest of the firewall and Docker rules stay untouched.
- Ranges from [ipdeny.com](https://www.ipdeny.com), refreshed on boot and daily by `ru-block.timer`.
- Open ports are detected from `sshd` and `amnezia-*` containers and kept in `/etc/ru-block.ports`. Add a missing one with `echo "udp 51820" >> /etc/ru-block.ports && ru-block-update`.

## Notes

- Russian sites will not open through the VPN: enable split tunneling on clients.
- In a cascade, run it on the exit nodes.
