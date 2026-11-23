#!/bin/sh
set -e

CONFIG_PATH="/etc/sing-box/config.json"
TEMP_DIR="/tmp/singbox-setup"
mkdir -p "$TEMP_DIR" "$(dirname $CONFIG_PATH)"

# ─── Validate env ───────────────────────────────────────────
for var in SUB_URL SSH_HOST SSH_USER; do
  eval val=\$$var
  if [ -z "$val" ]; then
    echo "❌ Missing required env: $var"
    exit 1
  fi
done

SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/etc/sing-box/ssh-key}"

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "❌ SSH key not found at $SSH_KEY_PATH"
  exit 1
fi

# ─── Preserve original Docker DNS for subscription fetch ───
if [ -f /tmp/resolv.conf.orig ]; then
  cat /tmp/resolv.conf.orig > /etc/resolv.conf
else
  cp /etc/resolv.conf /tmp/resolv.conf.orig
fi

# ─── Fetch subscription ────────────────────────────────────
echo "⬇️  Fetching subscription..."
wget -qO "$TEMP_DIR/sub.json" "$SUB_URL" 2>/dev/null || {
  echo "❌ Failed to fetch subscription from: $SUB_URL"
  exit 1
}

echo "📄 Downloaded subscription config"

# ─── Convert to sing-box outbounds ─────────────────────────
echo "🔄 Converting to sing-box format..."
python3 /convert.py "$TEMP_DIR/sub.json" "$TEMP_DIR/outbounds.json"

# ─── Read proxy outbounds ─────────────────────────────────
PROXY_OUTBOUNDS=$(cat "$TEMP_DIR/outbounds.json")

# Find the main proxy tag (urltest "auto" if exists, else first outbound)
PROXY_TAG=$(echo "$PROXY_OUTBOUNDS" | python3 -c "
import json, sys
obs = json.load(sys.stdin)
# prefer urltest/selector
for o in obs:
    if o['type'] in ('urltest', 'selector'):
        print(o['tag']); sys.exit()
# fallback to first proxy
if obs:
    print(obs[0]['tag'])
")

echo "🔗 Main proxy tag: $PROXY_TAG"

# ─── Build SSH outbound ───────────────────────────────────
SSH_OUTBOUND=$(python3 -c "
import json
print(json.dumps({
    'tag': 'ssh-exit',
    'type': 'ssh',
    'server': '$SSH_HOST',
    'server_port': $SSH_PORT,
    'user': '$SSH_USER',
    'private_key_path': '$SSH_KEY_PATH',
    'detour': '$PROXY_TAG'
}))
")

# ─── Merge into final config ─────────────────────────────
python3 -c "
import json

with open('/template.json') as f:
    config = json.load(f)

outbounds = json.loads('''$PROXY_OUTBOUNDS''')
ssh_ob = json.loads('''$SSH_OUTBOUND''')

# Add: proxy outbounds + SSH + direct
outbounds.append(ssh_ob)
outbounds.append({'type': 'direct', 'tag': 'direct'})

config['outbounds'] = outbounds

with open('$CONFIG_PATH', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f'✅ Final config: {len(outbounds)} outbounds')
"

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Config built successfully"
echo "  📡 Proxy:      $PROXY_TAG"
echo "  🔑 SSH exit:   $SSH_USER@$SSH_HOST:$SSH_PORT"
echo "  🛡️  Kill switch: strict_route=true"
echo "  🔗 Chain:      App → TUN → $PROXY_TAG → SSH → 🌐"
echo "═══════════════════════════════════════════"
echo ""

# ─── Validate config ──────────────────────────────────────
echo "🔍 Validating config..."
sing-box check -c "$CONFIG_PATH" && echo "✅ Config valid" || {
  echo "❌ Config validation failed:"
  cat "$CONFIG_PATH"
  exit 1
}

# ─── Route container DNS through TUN so sing-box hijacks it ─
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# ─── Run ──────────────────────────────────────────────────
echo "🚀 Starting sing-box..."
exec sing-box run -c "$CONFIG_PATH"
