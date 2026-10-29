# T3 Code on Alta

`t3code.nix` packages the upstream ARM64 CLI release (SHA-256 verified), without
Electron or npm at startup. The command is equivalent to:

```sh
t3 serve --host 0.0.0.0 --port 3773
```

It is a **systemd user service for alta**, not a root agent host. Lingering keeps
it running after SSH logout and starts the user manager at boot. Its identity,
provider settings and database remain under `/home/alta/.t3`; projects run with
Alta's normal home-directory access. Do not enable T3's separate service installer
on top of the Nix-managed unit.

## Access and management

- LAN: `http://alta.local:3773` (or Alta's current LAN IP).
- Pair from an SSH terminal: `ssh -x -o ClearAllForwardings=yes alta@alta.local 't3 pair'`.
  Treat the resulting one-time link as a password; do not save it in this repo.
- Status: `systemctl --user status t3code` as alta.
- Restart: `systemctl --user restart t3code` as alta.
- Logs: `journalctl --user -u t3code` as alta. Startup logs may contain pairing secrets.
- Configure and authenticate providers on **Alta**, not the connecting desktop.
  The server can start without a provider; actual agent turns require one.
- Update the release version and checksum in `t3code.nix`, rebuild and restart.
  Do not use `t3 update` to modify the Nix store installation.

`0.0.0.0` exposes every IPv4 interface. Alta's existing firewall permits all TCP
ports; this change does not add public forwarding, TLS, or T3 Connect. Use only a
trusted LAN/VPN. Pairing grants powerful host access. The hosted HTTPS app cannot
directly use a plain HTTP backend; use the desktop/mobile app or the LAN web UI.

## Initial deployment without switching unrelated services

The initial installation used the **exact Nix-built user unit**, linked and enabled
in `~alta/.config/systemd/user/`, plus `loginctl enable-linger alta`. A GC root at
`/nix/var/nix/gcroots/t3code-user-service` retains the unit and its dependency closure.
The CLI was also installed in alta's Nix profile. No full NixOS activation was
performed: building the full system also required unrelated ARM service builds.

On the next successful full Alta rebuild, remove the bootstrap user-local
`t3code.service` symlink and its `default.target.wants/t3code.service` symlink,
then run `systemctl --user daemon-reload` and `systemctl --user restart t3code`.
The NixOS-provided user unit/target then owns startup. Remove the bootstrap GC
root and the duplicate CLI profile entry only after checking the system-managed
`t3` and unit exist. User-local units take precedence over NixOS-provided ones,
so leaving the bootstrap link in place would mask future declarative updates.

## Primary references

- https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md
- https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md
- https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md
- https://github.com/pingdotgg/t3code/releases/tag/v0.1.5
