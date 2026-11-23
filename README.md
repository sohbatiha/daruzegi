<p align="center">
  <img src="assets/daruzegi.jpg" alt="Daruzegi (دَریوزِگی)" width="320" />
</p>

<h1 align="center">Daruzegi (دَریوزِگی)</h1>

<p align="center">
  <strong>T3 Code Workspace (<code>sing-box</code> Proxy Chain)</strong><br />
  <em>Pronunciation: <strong>/dæɾ.juː.zeˈɡiː/</strong> · <code>dar-yoo-ze-GEE</code> (Persian: <strong>دَریوزِگی</strong> — "begging / panhandling")</em>
</p>

<p align="center">
  🌐 <strong>Language:</strong> <strong>English</strong> | <a href="README.fa.md">فارسی</a>
</p>

An isolated Docker workspace for running **T3 Code** (with **Claude Code** and **OpenAI Codex**) and a hardened **Firefox** browser where all outbound network traffic and DNS queries are forced through a chained tunnel:

```text
T3 Code (container :3773)    ──► TUN (tun0, strict_route) ──┐
                                                             ├──► auto (VLESS / VMess / Trojan / SS) ──► SSH Exit Node ──► Internet
Hardened Firefox (host)      ──► SOCKS5 (127.0.0.1:1080)  ──┘
```

## Features

- **T3 Code Web UI + Coding Agents**: Runs `t3 serve` (bound locally to `127.0.0.1:3773`) with both `@anthropic-ai/claude-code` and `@openai/codex` preinstalled, plus `t3-pair` / `make pair` for generating login pairing links.
- **Flexible Proxy Modes (`sub`, `uri`, `direct`)**:
  - `sub` *(default)*: Fetches an Xray/V2Ray subscription (Sanaei JSON arrays, standard JSON, sing-box JSON, or base64/plain URI lists), converts outbounds to `sing-box` 1.14+ format, selects the fastest node via `urltest` (`auto`), and tunnels an SSH exit connection through it.
  - `uri`: Connects via a single share link (`vless://`, `vmess://`, `trojan://`, or `ss://`) defined in `PROXY_URI`, then tunnels through SSH.
  - `direct`: Bypasses the upstream proxy/subscription entirely and connects directly to your SSH exit node.
- **Transparent TUN Routing & Kill Switch**: The `t3code` container shares `singbox`'s network namespace (`network_mode: "service:singbox"`) and waits until `singbox` passes its healthcheck (`tun0` up + port `1080` listening). All container traffic is routed through `tun0` with `strict_route: true` — even tools ignoring proxy environment variables cannot bypass the tunnel.
- **No DNS Leaks**: Container DNS is pointed to `1.1.1.1` so queries enter `tun0`, get intercepted via `hijack-dns`, and resolve over DoH (`https://1.1.1.1/dns-query`) through `ssh-exit`. Proxy server hostnames resolve separately via Docker's local resolver (`default_domain_resolver`) to avoid bootstrap loops.
- **Host SOCKS5/HTTP Proxy + Hardened Firefox**: Exposes a `mixed` inbound on `127.0.0.1:1080` for macOS host apps and includes `make firefox` to launch an isolated Firefox profile with remote SOCKS5 DNS, WebRTC disabled, geolocation disabled, `resistFingerprinting`, and matching timezone (`Europe/Helsinki`).
- **Single Unified Persistent Data Folder (`DATA_DIR`)**: Mounts the entire container home directory (`/home/node`) to a single host folder (`DATA_DIR`, default `./data`), so all Claude CLI, Codex, and T3 Code files — including skills (`.claude/skills`, `.codex/skills`, `.agents/skills`), plugins, MCP configs, auth sessions, `.config`, `.local/bin`, `.npm-global`, `.ssh`, and shell history — survive `docker-compose` edits, rebuilds, restarts, and `docker compose down -v`.
- **Dynamic Project Mounts via `.env`**: List one or more host project folders in `PROJECTS` to mount them automatically under `/workspace/<folder-name>`.

## Project Structure

```text
.
├── Dockerfile              # Node 22 + t3 + @anthropic-ai/claude-code + @openai/codex
├── entrypoint.sh           # Git identity, safe.directory, and optional Codex API-key login
├── t3-pair                 # Helper installed in container to issue T3 pairing links
├── pair.sh                 # Host shortcut for issuing T3 pairing links
├── docker-compose.yaml     # Unified stack: singbox gateway + t3code container
├── Makefile                # Helper commands (run `make` for help)
├── README.md               # English documentation
├── README.fa.md            # Persian documentation
├── .env.example            # Required environment variables template
├── .gitignore              # Ignores .env, data/, and generated docker-compose.override.yaml
├── assets/
│   └── daruzegi.jpg        # Project artwork
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
- *(Optional, depending on `PROXY_MODE`)* An Xray/V2Ray/sing-box subscription URL (`sub`) or a single `vless://` / `vmess://` / `trojan://` / `ss://` link (`uri`)
- An SSH exit server with key-based authentication (`~/.ssh/id_rsa` or custom key path) — enabled by default
- *(Optional)* Firefox installed at `/Applications/Firefox.app` (macOS) for `make firefox`

## Setup

1. Create your `.env` file from the template:
   ```bash
   make setup
   ```

2. Edit `.env` with your proxy mode, SSH exit server, T3 settings, Git identity, and project paths:
   ```env
   # Upstream Proxy Mode: sub | uri | direct
   PROXY_MODE=sub

   # Subscription URL (when PROXY_MODE=sub)
   SUB_URL=https://sub.example.com/json/YOUR_TOKEN
   # URL-test interval for subscription nodes (e.g. 30s, 5m, 1h)
   SUB_TEST_INTERVAL=5m

   # Single proxy URI (when PROXY_MODE=uri) — supports vless://, vmess://, trojan://, ss://
   # PROXY_URI=vless://uuid@example.com:443?security=reality&sni=example.com&pbk=...&sid=...&fp=chrome#node

   # SSH Tunnel (final exit node)
   # WARNING: Always enabled by default (SSH_ENABLED=true). Setting SSH_ENABLED=false
   # disables the SSH exit hop and WILL LEAK your real IP if combined with PROXY_MODE=direct.
   # SSH_ENABLED=true
   SSH_HOST=1.2.3.4
   SSH_PORT=22
   SSH_USER=root
   SSH_KEY_FILE=~/.ssh/id_rsa

   # Proxy & T3 Code
   SOCKS_PORT=1080
   DATA_DIR=./data
   T3_PORT=3773
   T3_CPUS=0
   # T3_PUBLIC_URL=http://localhost:3773
   T3_PAIRING_TTL=1h

   # Coding Agents (optional — leave empty to log in interactively)
   CLAUDE_CODE_OAUTH_TOKEN=
   OPENAI_API_KEY=

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

4. Verify the tunnel, exit IP, DNS, and T3 Code endpoint:
   ```bash
   make check
   ```
   All three IP checks (Host SOCKS5, Container `curl`, and Container `curl --noproxy "*"`) should return your `SSH_HOST` IP, and the T3 Code endpoint check should respond over `http://127.0.0.1:3773`.

5. Generate a T3 Code login link and authenticate your coding agents:
   ```bash
   make pair          # prints http://localhost:3773/... pairing link (make pair TTL=30d)
   make claude-login  # run /login inside Claude Code
   make codex-login   # log in to Codex with ChatGPT
   ```

## Commands

Run `make` (or `make help`) to display all available targets:

| Command | Description |
| :--- | :--- |
| `make` / `make help` | Show available commands |
| `make setup` | Create `.env` from `.env.example` |
| `make sync-projects` | Regenerate `docker-compose.override.yaml` from `PROJECTS` in `.env` |
| `make up` | Sync project mounts and start containers in the background |
| `make build` | Sync project mounts, rebuild images, and start containers |
| `make down` | Stop and remove containers |
| `make restart` | Restart containers (re-fetches subscription on `singbox` start) |
| `make ps` | Show container status |
| `make pair` | Issue a T3 Code login link (`make pair TTL=30d`) |
| `make claude` / `make claude-login` | Launch `claude` CLI inside `t3code` |
| `make codex-login` | Log in to Codex with ChatGPT (`--device-auth`) |
| `make shell` | Open an interactive `bash` shell inside `t3code` |
| `make firefox` | Launch hardened Firefox routed through `127.0.0.1:1080` |
| `make check` | Verify SOCKS5 IP, container IP, transparent TUN, DNS, and T3 local port |
| `make logs` | Follow logs for all containers |
| `make logs-singbox` | Follow `singbox` container logs |
| `make logs-t3` | Follow `t3code` container logs |
| `make fix-perms` | Give `node` (container user) ownership of `/workspace` |

## Troubleshooting

- **Check startup logs**:
  ```bash
  make logs
  ```
- **Subscription updated on panel**: Run `make restart` so `singbox` re-downloads and converts the latest subscription.
- **First request takes a few seconds**: On initial startup, `urltest` benchmarks the subscription nodes and establishes the first SSH tunnel handshake; subsequent requests reuse the active tunnel.
- **SSH key permission or mount issues**: Ensure `SSH_KEY_FILE` in `.env` points to a readable private key on the host without a passphrase (or update `singbox-chain/entrypoint.sh` if using a passphrase).
