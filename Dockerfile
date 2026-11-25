FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client \
        ripgrep jq less procps vim-tiny \
        xvfb openbox x11vnc novnc websockify dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# Auto-connect & scale when visiting http://127.0.0.1:<BROWSER_PORT>/
RUN printf '<!doctype html><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale">\n' \
    > /usr/share/novnc/index.html

# t3code + coding agents + Playwright MCP (rebuild image to update: docker compose build --pull --no-cache)
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npm install -g t3 @anthropic-ai/claude-code @openai/codex @playwright/mcp \
    && npm cache clean --force

# Antigravity CLI (agy) — installed in /usr/local/bin so it persists outside the /home/node volume
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin \
    && rm -rf /root/.cache/antigravity

RUN /usr/local/lib/node_modules/@playwright/mcp/node_modules/.bin/playwright-core install --with-deps chromium \
    && chmod -R a+rX /ms-playwright \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY t3-pair /usr/local/bin/t3-pair
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/t3-pair \
    && mkdir -p /tmp/.X11-unix /workspace /home/node/.claude /home/node/.codex /home/node/.gemini/config /home/node/.gemini/antigravity-cli /home/node/.t3 /home/node/.agents /home/node/.local/bin /home/node/.npm-global/bin /home/node/.playwright-profile \
    && chmod 1777 /tmp/.X11-unix \
    && chown -R node:node /workspace /home/node

USER node
ENV HOME=/home/node \
    DISPLAY=:99 \
    NPM_CONFIG_PREFIX=/home/node/.npm-global \
    PATH="/home/node/.npm-global/bin:/home/node/.local/bin:${PATH}"
WORKDIR /workspace
EXPOSE 3773 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["t3", "serve", "--host", "0.0.0.0", "--port", "3773", "/workspace"]
