SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env

COMPOSE         := docker compose
FIREFOX_PROFILE := $(HOME)/ff-claude-profile
TIMEZONE        := $(or $(TZ),Europe/Helsinki)
SOCKS_PORT      := $(or $(SOCKS_PORT),1080)
T3_PORT         := $(or $(T3_PORT),3773)
BROWSER_PORT    := $(or $(BROWSER_PORT),6080)

.PHONY: help setup sync-projects up build down restart ps browser firefox pair claude claude-login codex-login shell check logs logs-singbox logs-t3 fix-perms

help: ## Show available commands
	@echo "T3 Code Workspace (sing-box → VLESS/VMess → SSH Exit)"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Create .env from .env.example
	@if [ -f .env ]; then echo ".env already exists"; else cp .env.example .env && chmod 600 .env && echo "created .env — edit it"; fi

sync-projects: ## Generate docker-compose.override.yaml from PROJECTS in .env
	@python3 scripts/sync-projects.py

up: sync-projects ## Start containers in background
	$(COMPOSE) up -d --remove-orphans

build: sync-projects ## Rebuild images and start containers
	$(COMPOSE) up -d --build --remove-orphans

down: ## Stop and remove containers
	$(COMPOSE) down

restart: ## Restart containers
	$(COMPOSE) restart

ps: ## Show container status
	$(COMPOSE) ps

pair: ## Print a T3 Code login link (make pair TTL=30d)
	$(COMPOSE) exec t3code t3-pair $(TTL)

claude: ## Run Claude Code inside t3code container
	$(COMPOSE) exec -it t3code claude

claude-login: ## Log in to Claude Code (run /login inside)
	$(COMPOSE) exec -it t3code claude

codex-login: ## Log in to Codex with ChatGPT
	$(COMPOSE) exec -it t3code codex login --device-auth

shell: ## Open interactive bash shell inside t3code
	$(COMPOSE) exec -it t3code bash

browser: ## Open live container browser (noVNC); optional: make browser URL=https://...
	@if [ -n "$(URL)" ]; then \
		if $(COMPOSE) exec -T t3code pgrep -f 'playwright-profile' >/dev/null 2>&1; then \
			echo "Chromium is already running inside t3code (opening live view)..."; \
		else \
			$(COMPOSE) exec -d -e TARGET_URL="$(URL)" t3code sh -c '\
				CHROME="$$(node -e "const p=require(require.resolve(\"playwright-core\",{paths:[\"/usr/local/lib/node_modules/@playwright/mcp\"]}));console.log(p.chromium.executablePath())")"; \
				exec "$$CHROME" --no-sandbox --user-data-dir="$$HOME/.playwright-profile" --window-size=1280,760 --no-first-run "$$TARGET_URL" >/tmp/chromium-manual.log 2>&1'; \
			echo "Launched Chromium in t3code for $(URL) — close the browser window when done logging in."; \
		fi; \
	fi
	@open "http://127.0.0.1:$(BROWSER_PORT)/vnc.html?autoconnect=true&resize=scale"
	@echo "Live browser viewer: http://127.0.0.1:$(BROWSER_PORT)/vnc.html?autoconnect=true&resize=scale"

firefox: ## Launch hardened Firefox using SOCKS5 proxy (127.0.0.1:1080)
	@mkdir -p $(FIREFOX_PROFILE)
	@printf 'user_pref("network.proxy.type", 1);\n\
user_pref("network.proxy.socks", "127.0.0.1");\n\
user_pref("network.proxy.socks_port", $(SOCKS_PORT));\n\
user_pref("network.proxy.socks_version", 5);\n\
user_pref("network.proxy.socks_remote_dns", true);\n\
user_pref("network.trr.mode", 5);\n\
user_pref("media.peerconnection.enabled", false);\n\
user_pref("geo.enabled", false);\n\
user_pref("permissions.default.geo", 2);\n\
user_pref("geo.provider.use_corelocation", false);\n\
user_pref("geo.wifi.uri", "");\n\
user_pref("privacy.resistFingerprinting", true);\n\
user_pref("intl.accept_languages", "en-US, en");\n' > $(FIREFOX_PROFILE)/user.js
	@TZ="$(TIMEZONE)" /Applications/Firefox.app/Contents/MacOS/firefox --profile $(FIREFOX_PROFILE) --no-remote --new-instance >/dev/null 2>&1 &
	@echo "Hardened Firefox launched on 127.0.0.1:$(SOCKS_PORT) (TZ=$(TIMEZONE))"

check: ## Verify SOCKS5 IP, container IP, TUN routing, DNS, and T3 port
	@echo "--- Host SOCKS5 Proxy IP (127.0.0.1:$(SOCKS_PORT)) ---"
	@curl -s --max-time 10 --socks5-hostname 127.0.0.1:$(SOCKS_PORT) https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Container IP (t3code) ---"
	@docker exec t3code curl -s --max-time 10 https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Transparent TUN Test (--noproxy '*', Expecting Same Exit IP) ---"
	@docker exec t3code curl -s --noproxy "*" --max-time 10 https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Container DNS Config ---"
	@docker exec t3code cat /etc/resolv.conf
	@echo ""
	@echo "--- T3 Code Local Endpoint (http://127.0.0.1:$(T3_PORT)) ---"
	@curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:$(T3_PORT) || echo "Failed"
	@echo ""
	@echo "--- Browser Live View (http://127.0.0.1:$(BROWSER_PORT)) ---"
	@curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:$(BROWSER_PORT)/vnc.html || echo "Failed"

logs: ## Follow logs for all containers
	$(COMPOSE) logs -f --tail=200

logs-singbox: ## Follow singbox container logs
	docker logs -f --tail=200 singbox

logs-t3: ## Follow t3code container logs
	docker logs -f --tail=200 t3code

fix-perms: ## Give node (container user) ownership of all projects
	docker exec -u 0 t3code chown -R node:node /workspace
