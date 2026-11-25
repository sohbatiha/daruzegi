#!/bin/sh
set -e

# Seed shell dotfiles on first run in a fresh persistent home directory
for f in .bashrc .profile .bash_logout; do
  [ ! -e "$HOME/$f" ] && [ -f "/etc/skel/$f" ] && cp "/etc/skel/$f" "$HOME/$f"
done

# Ensure standard agent, skill, config, and local binary directories exist
mkdir -p \
  "$HOME/.claude/skills" \
  "$HOME/.codex/skills" \
  "$HOME/.gemini/config/skills" \
  "$HOME/.gemini/antigravity-cli" \
  "$HOME/.agents/skills" \
  "$HOME/.t3" \
  "$HOME/.config" \
  "$HOME/.local/bin" \
  "$HOME/.local/share" \
  "$HOME/.cache" \
  "$HOME/.npm-global/bin" \
  "$HOME/.playwright-profile"

# Clear stale Chromium profile locks left by an ungraceful container stop
rm -f \
  "$HOME/.playwright-profile/SingletonLock" \
  "$HOME/.playwright-profile/SingletonSocket" \
  "$HOME/.playwright-profile/SingletonCookie"

# Start virtual X11 display + lightweight WM + noVNC so headed Chromium is viewable on 127.0.0.1:<BROWSER_PORT>
DISPLAY_NUM="${DISPLAY#:}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
if ! pgrep -x Xvfb >/dev/null 2>&1; then
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
  Xvfb ":${DISPLAY_NUM}" -screen 0 1280x800x24 -ac +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
  i=0
  while [ ! -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  openbox >/tmp/openbox.log 2>&1 &
  x11vnc -display ":${DISPLAY_NUM}" -rfbport 5900 -listen 127.0.0.1 -forever -shared -nopw -noxdamage -quiet >/tmp/x11vnc.log 2>&1 &
  websockify --web=/usr/share/novnc "0.0.0.0:${BROWSER_PORT:-6080}" 127.0.0.1:5900 >/tmp/novnc.log 2>&1 &
fi

# Git identity for commits made by agents (optional, from .env)
[ -n "$GIT_USER_NAME" ]  && git config --global user.name  "$GIT_USER_NAME"
[ -n "$GIT_USER_EMAIL" ] && git config --global user.email "$GIT_USER_EMAIL"
git config --global log.date local
git config --global safe.directory '*'

# Unset empty auth variables so CLIs cleanly fall back to stored logins
[ -z "$CLAUDE_CODE_OAUTH_TOKEN" ] && unset CLAUDE_CODE_OAUTH_TOKEN
[ -z "$ANTHROPIC_API_KEY" ]       && unset ANTHROPIC_API_KEY
[ -z "$OPENAI_API_KEY" ]          && unset OPENAI_API_KEY
[ -z "$GEMINI_API_KEY" ]          && unset GEMINI_API_KEY
[ -z "$GOOGLE_GEMINI_BASE_URL" ]  && unset GOOGLE_GEMINI_BASE_URL

# Codex: log in with API key from .env once (skipped if already logged in, e.g. via `codex login --device-auth`)
if [ -n "$OPENAI_API_KEY" ] && [ ! -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then
  printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null 2>&1 \
    && echo "[entrypoint] codex logged in with OPENAI_API_KEY" \
    || echo "[entrypoint] WARN: codex API-key login failed"
fi

# Antigravity CLI: sync GEMINI_API_KEY mode in ~/.gemini/antigravity-cli/settings.json
AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
if [ -n "$GEMINI_API_KEY" ]; then
  [ -f "$AGY_SETTINGS" ] || printf '{}\n' > "$AGY_SETTINGS"
  if jq '.modelProvider = "gemini"' "$AGY_SETTINGS" > "${AGY_SETTINGS}.tmp" 2>/dev/null; then
    mv "${AGY_SETTINGS}.tmp" "$AGY_SETTINGS"
    echo "[entrypoint] antigravity CLI configured for GEMINI_API_KEY"
  else
    rm -f "${AGY_SETTINGS}.tmp"
    echo "[entrypoint] WARN: failed to update $AGY_SETTINGS"
  fi
elif [ -f "$AGY_SETTINGS" ] && jq -e '.modelProvider == "gemini"' "$AGY_SETTINGS" >/dev/null 2>&1; then
  if jq 'del(.modelProvider)' "$AGY_SETTINGS" > "${AGY_SETTINGS}.tmp" 2>/dev/null; then
    mv "${AGY_SETTINGS}.tmp" "$AGY_SETTINGS"
    echo "[entrypoint] antigravity CLI reverted to OAuth authentication"
  else
    rm -f "${AGY_SETTINGS}.tmp"
  fi
fi

# Antigravity CLI: register Playwright MCP in global config once (persisted in ~/.gemini/config/mcp_config.json)
AGY_MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"
if ! jq -e '.mcpServers.playwright' "$AGY_MCP_CONFIG" >/dev/null 2>&1; then
  [ -f "$AGY_MCP_CONFIG" ] || printf '{}\n' > "$AGY_MCP_CONFIG"
  if jq --arg display "${DISPLAY:-:99}" --arg profile "$HOME/.playwright-profile" \
    '.mcpServers = (.mcpServers // {}) | .mcpServers.playwright = {
      command: "playwright-mcp",
      args: [
        "--browser", "chromium",
        "--no-sandbox",
        "--ignore-https-errors",
        "--viewport-size", "1280x760",
        "--output-dir", "/tmp/playwright-mcp",
        "--user-data-dir", $profile
      ],
      env: {
        DISPLAY: $display
      }
    }' "$AGY_MCP_CONFIG" > "${AGY_MCP_CONFIG}.tmp" 2>/dev/null; then
    mv "${AGY_MCP_CONFIG}.tmp" "$AGY_MCP_CONFIG"
    echo "[entrypoint] registered playwright MCP for antigravity"
  else
    rm -f "${AGY_MCP_CONFIG}.tmp"
    echo "[entrypoint] WARN: failed to register playwright MCP for antigravity"
  fi
fi

# Claude Code: register Playwright MCP in user scope once (persisted in $CLAUDE_CONFIG_DIR/.claude.json)
CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json"
if ! jq -e '.mcpServers.playwright' "$CLAUDE_JSON" >/dev/null 2>&1; then
  claude mcp add -s user playwright -e "DISPLAY=${DISPLAY:-:99}" -- \
    playwright-mcp \
    --browser chromium \
    --no-sandbox \
    --ignore-https-errors \
    --viewport-size 1280x760 \
    --output-dir /tmp/playwright-mcp \
    --user-data-dir "$HOME/.playwright-profile" >/dev/null 2>&1 \
    && echo "[entrypoint] registered playwright MCP (user scope)" \
    || echo "[entrypoint] WARN: failed to register playwright MCP"
fi

exec "$@"
