SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env

FIREFOX_PROFILE := $(HOME)/ff-claude-profile
TIMEZONE        := $(or $(TZ),Europe/Helsinki)
SOCKS_PORT      := $(or $(SOCKS_PORT),1080)

.PHONY: help sync-projects up build down restart firefox claude shell check logs

help: ## Show available commands
	@echo "Claude Workspace (sing-box → VLESS/VMess → SSH Exit)"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

sync-projects: ## Generate docker-compose.override.yaml from PROJECTS in .env
	@python3 scripts/sync-projects.py

up: sync-projects ## Start containers in background
	docker compose up -d

build: sync-projects ## Rebuild images and start containers
	docker compose up -d --build

down: ## Stop and remove containers
	docker compose down

restart: ## Restart containers
	docker compose restart

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

claude: ## Run Claude Code inside claude-workspace container
	docker exec -it claude-workspace claude

shell: ## Open interactive bash shell inside claude-workspace
	docker exec -it claude-workspace bash

check: ## Verify host SOCKS5 IP, container IP, TUN routing, and DNS
	@echo "--- Host SOCKS5 Proxy IP (127.0.0.1:$(SOCKS_PORT)) ---"
	@curl -s --max-time 10 --socks5-hostname 127.0.0.1:$(SOCKS_PORT) https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Container IP (claude-workspace) ---"
	@docker exec claude-workspace curl -s --max-time 10 https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Transparent TUN Test (--noproxy '*', Expecting Same Exit IP) ---"
	@docker exec claude-workspace curl -s --noproxy "*" --max-time 10 https://api.ipify.org || echo "Failed"
	@echo ""
	@echo "--- Container DNS Config ---"
	@docker exec claude-workspace cat /etc/resolv.conf

logs: ## Follow singbox container logs
	docker logs -f singbox
