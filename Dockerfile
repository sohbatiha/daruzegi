FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client \
        ripgrep jq less procps vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# t3code + coding agents (rebuild image to update: docker compose build --pull --no-cache)
RUN npm install -g t3 @anthropic-ai/claude-code @openai/codex \
    && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY t3-pair /usr/local/bin/t3-pair
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/t3-pair \
    && mkdir -p /workspace /home/node/.claude /home/node/.codex /home/node/.t3 /home/node/.agents /home/node/.local/bin /home/node/.npm-global/bin \
    && chown -R node:node /workspace /home/node

USER node
ENV HOME=/home/node \
    NPM_CONFIG_PREFIX=/home/node/.npm-global \
    PATH="/home/node/.npm-global/bin:/home/node/.local/bin:${PATH}"
WORKDIR /workspace
EXPOSE 3773

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["t3", "serve", "--host", "0.0.0.0", "--port", "3773", "/workspace"]
