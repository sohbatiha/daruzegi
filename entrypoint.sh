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
  "$HOME/.agents/skills" \
  "$HOME/.t3" \
  "$HOME/.config" \
  "$HOME/.local/bin" \
  "$HOME/.local/share" \
  "$HOME/.cache" \
  "$HOME/.npm-global/bin"

# Git identity for commits made by agents (optional, from .env)
[ -n "$GIT_USER_NAME" ]  && git config --global user.name  "$GIT_USER_NAME"
[ -n "$GIT_USER_EMAIL" ] && git config --global user.email "$GIT_USER_EMAIL"
git config --global log.date local
git config --global safe.directory '*'

# Unset empty auth variables so CLIs cleanly fall back to stored logins
[ -z "$CLAUDE_CODE_OAUTH_TOKEN" ] && unset CLAUDE_CODE_OAUTH_TOKEN
[ -z "$ANTHROPIC_API_KEY" ]       && unset ANTHROPIC_API_KEY
[ -z "$OPENAI_API_KEY" ]          && unset OPENAI_API_KEY

# Codex: log in with API key from .env once (skipped if already logged in, e.g. via `codex login --device-auth`)
if [ -n "$OPENAI_API_KEY" ] && [ ! -f "${CODEX_HOME:-$HOME/.codex}/auth.json" ]; then
  printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null 2>&1 \
    && echo "[entrypoint] codex logged in with OPENAI_API_KEY" \
    || echo "[entrypoint] WARN: codex API-key login failed"
fi

exec "$@"
