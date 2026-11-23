🌐 **Language:** **English** | [فارسی](README.fa.md)

# Claude Workspace (`sing-box` Proxy Chain)

An isolated Docker workspace for running **Claude Code** and a hardened **Firefox** browser where all network traffic and DNS queries are forced through a chained tunnel:

```text
Claude Workspace (container) ──► TUN (tun0, strict_route) ──┐
                                                             ├──► auto (VLESS / VMess / Trojan / SS) ──► SSH Exit Node ──► Internet
Hardened Firefox (host)      ──► SOCKS5 (127.0.0.1:1080)  ──┘
```

## Features

- **Chained Proxy Architecture**: Fetches an Xray/V2Ray subscription (including Sanaei panel JSON arrays), converts outbounds to `sing-box` 1.14+ format, selects the fastest node via `urltest` (`auto`), and tunnels an SSH exit connection through it.
- **Transparent TUN Routing & Kill Switch**: The `claude-workspace` container shares `singbox`'s network namespace (`network_mode: "service:singbox"`) and waits until `singbox` passes its healthcheck (`tun0` up + port `1080` listening). All container traffic is routed through `tun0` with `strict_route: true` — even tools ignoring proxy environment variables cannot bypass the tunnel.
- **No DNS Leaks**: Container DNS is pointed to `1.1.1.1` so queries enter `tun0`, get intercepted via `hijack-dns`, and resolve over DoH (`https://1.1.1.1/dns-query`) through `ssh-exit`. Proxy server hostnames resolve separately via Docker's local resolver (`default_domain_resolver`) to avoid bootstrap loops.
- **Host SOCKS5/HTTP Proxy + Hardened Firefox**: Exposes a `mixed` inbound on `127.0.0.1:1080` for macOS host apps and includes `make firefox` to launch an isolated Firefox profile with remote SOCKS5 DNS, WebRTC disabled, geolocation disabled, `resistFingerprinting`, and matching timezone (`Europe/Helsinki`).
- **Persistent Claude Config**: Stores `/root/.claude` in the `claude-config` Docker volume so login sessions and settings persist across rebuilds.

## Project Structure

```text
.
├── Dockerfile              # Node 20 + git + curl + @anthropic-ai/claude-code
├── docker-compose.yaml     # Unified stack: singbox gateway + claude-workspace
├── Makefile                # Helper commands (run `make` for help)
├── README.md               # English documentation
├── README.fa.md            # Persian documentation
├── .env.example            # Required environment variables template
├── .gitignore              # Ignores .env and generated docker-compose.override.yaml
├── scripts/
│   └── sync-projects.py    # Generates docker-compose.override.yaml from PROJECTS in .env
└── singbox-chain/
    ├── Dockerfile          # sing-box + Python 3.12 (Alpine)
    ├── convert.py          # Xray/V2Ray JSON → sing-box outbounds converter
    ├── entrypoint.sh       # Subscription fetch, config build/check, DNS setup
    └── template.json       # sing-box 1.14+ base config (TUN, mixed, DNS, routing)
```

## Prerequisites

- Docker & Docker Compose
- An Xray/V2Ray JSON subscription URL (or sing-box JSON config)
- An SSH exit server with key-based authentication (`~/.ssh/id_rsa` or custom key path)
- *(Optional)* Firefox installed at `/Applications/Firefox.app` (macOS) for `make firefox`

## Setup

1. Create your `.env` file from the template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your subscription URL, SSH exit server, workspace settings, and Git identity:
   ```env
   # Subscription (Xray/V2Ray JSON, e.g. from Sanaei panel)
   SUB_URL=https://sub.example.com/json/YOUR_TOKEN

   # SSH Tunnel (final exit node)
   SSH_HOST=1.2.3.4
   SSH_PORT=22
   SSH_USER=root
   SSH_KEY_FILE=~/.ssh/id_rsa

   # Proxy
   SOCKS_PORT=1080

   # Workspace Environment
   TZ=Europe/Helsinki
   WORKSPACE_LANG=en_US.UTF-8
   WORKSPACE_TERM=xterm-256color

   # Git Identity
   GIT_USER_NAME=your-name
   GIT_USER_EMAIL=you@example.com

   # Projects (comma-separated host paths → mounted to /workspace/<folder-name>)
   # Use /path/to/dir:custom-name to override the folder name inside /workspace
   PROJECTS=/path/to/project-a,/other/path/project-b:custom-b
   ```

3. Build and start the stack:
   ```bash
   make build
   ```

4. Verify the tunnel, exit IP, and DNS:
   ```bash
   make check
   ```
   All three IP checks (Host SOCKS5, Container `curl`, and Container `curl --noproxy "*"`) should return your `SSH_HOST` IP.

## Commands

Run `make` (or `make help`) to display all available targets:

| Command | Description |
| :--- | :--- |
| `make` / `make help` | Show available commands |
| `make sync-projects` | Regenerate `docker-compose.override.yaml` from `PROJECTS` in `.env` |
| `make up` | Sync project mounts and start containers in the background |
| `make build` | Sync project mounts, rebuild images, and start containers |
| `make down` | Stop and remove containers |
| `make restart` | Restart containers (re-fetches subscription on `singbox` start) |
| `make claude` | Launch `claude` CLI inside `claude-workspace` |
| `make shell` | Open an interactive `bash` shell inside `claude-workspace` |
| `make firefox` | Launch hardened Firefox routed through `127.0.0.1:1080` |
| `make check` | Verify host SOCKS5 IP, container IP, transparent TUN, and DNS config |
| `make logs` | Follow `singbox` container logs |

## Troubleshooting

- **Check sing-box startup and proxy selection**:
  ```bash
  make logs
  ```
- **Subscription updated on panel**: Run `make restart` so `singbox` re-downloads and converts the latest subscription.
- **First request takes a few seconds**: On initial startup, `urltest` benchmarks the subscription nodes and establishes the first SSH tunnel handshake; subsequent requests reuse the active tunnel.
- **SSH key permission or mount issues**: Ensure `SSH_KEY_FILE` in `.env` points to a readable private key on the host without a passphrase (or update `singbox-chain/entrypoint.sh` if using a passphrase).
