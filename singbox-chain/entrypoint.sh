#!/bin/sh
set -e

CONFIG_PATH="/etc/sing-box/config.json"
TEMP_DIR="/tmp/singbox-setup"
mkdir -p "$TEMP_DIR" "$(dirname "$CONFIG_PATH")"

# ─── Normalize modes ────────────────────────────────────────
PROXY_MODE=$(printf '%s' "${PROXY_MODE:-sub}" | tr '[:upper:]' '[:lower:]')
case "$PROXY_MODE" in
  sub|subscription) PROXY_MODE="sub" ;;
  uri|single|config) PROXY_MODE="uri" ;;
  direct) PROXY_MODE="direct" ;;
  *)
    echo "❌ Invalid PROXY_MODE: '$PROXY_MODE' (expected: sub, uri, or direct)"
    exit 1
    ;;
esac

SSH_ENABLED_RAW=$(printf '%s' "${SSH_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')
case "$SSH_ENABLED_RAW" in
  false|0|no|off) SSH_ENABLED="false" ;;
  *) SSH_ENABLED="true" ;;
esac

SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-/etc/sing-box/ssh-key}"
SUB_TEST_INTERVAL="${SUB_TEST_INTERVAL:-5m}"
export SUB_TEST_INTERVAL

# ─── Validate required env ──────────────────────────────────
if [ "$PROXY_MODE" = "sub" ] && [ -z "${SUB_URL:-}" ]; then
  echo "❌ Missing required env for PROXY_MODE=sub: SUB_URL"
  exit 1
fi

if [ "$PROXY_MODE" = "uri" ] && [ -z "${PROXY_URI:-}" ]; then
  echo "❌ Missing required env for PROXY_MODE=uri: PROXY_URI"
  exit 1
fi

if [ "$SSH_ENABLED" = "true" ]; then
  for var in SSH_HOST SSH_USER; do
    eval val=\$$var
    if [ -z "$val" ]; then
      echo "❌ Missing required env for SSH_ENABLED=true: $var"
      exit 1
    fi
  done

  if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ SSH key not found at $SSH_KEY_PATH"
    exit 1
  fi
fi

# ─── Security warnings if SSH exit is disabled ──────────────
if [ "$SSH_ENABLED" = "false" ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  if [ "$PROXY_MODE" = "direct" ]; then
    echo "  🚨 CRITICAL WARNING: DIRECT MODE WITHOUT SSH EXIT!"
    echo "  Both PROXY_MODE=direct and SSH_ENABLED=false are active."
    echo "  ALL traffic goes directly from your real IP — YOUR IP WILL LEAK!"
  else
    echo "  ⚠️  WARNING: SSH_ENABLED=false — SSH exit proxy is DISABLED!"
    echo "  Traffic exits directly from the upstream proxy without SSH."
    echo "  Disabling SSH reduces isolation and may expose your IP."
  fi
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
fi

# ─── Preserve original Docker DNS ───────────────────────────
if [ -f /tmp/resolv.conf.orig ]; then
  cat /tmp/resolv.conf.orig > /etc/resolv.conf
else
  cp /etc/resolv.conf /tmp/resolv.conf.orig
fi

# ─── Prepare upstream proxy outbounds (if not direct) ───────
OUTBOUNDS_FILE=""
if [ "$PROXY_MODE" = "sub" ]; then
  echo "⬇️  Fetching subscription..."
  wget -qO "$TEMP_DIR/sub.input" "$SUB_URL" 2>/dev/null || {
    echo "❌ Failed to fetch subscription from: $SUB_URL"
    exit 1
  }
  echo "📄 Downloaded subscription config"
  echo "🔄 Converting to sing-box format..."
  python3 /convert.py "$TEMP_DIR/sub.input" "$TEMP_DIR/outbounds.json"
  OUTBOUNDS_FILE="$TEMP_DIR/outbounds.json"
elif [ "$PROXY_MODE" = "uri" ]; then
  echo "🔗 Parsing single proxy config (PROXY_URI)..."
  printf '%s\n' "$PROXY_URI" > "$TEMP_DIR/uri.input"
  python3 /convert.py "$TEMP_DIR/uri.input" "$TEMP_DIR/outbounds.json"
  OUTBOUNDS_FILE="$TEMP_DIR/outbounds.json"
else
  echo "➡️  PROXY_MODE=direct: skipping upstream proxy/subscription"
fi

# ─── Build final sing-box config ────────────────────────────
export PROXY_MODE SSH_ENABLED SSH_HOST SSH_PORT SSH_USER SSH_KEY_PATH OUTBOUNDS_FILE CONFIG_PATH

CHAIN_DESC=$(python3 - <<'PY'
import json
import os

proxy_mode = os.environ["PROXY_MODE"]
ssh_enabled = os.environ["SSH_ENABLED"] == "true"
outbounds_file = os.environ.get("OUTBOUNDS_FILE", "")
config_path = os.environ["CONFIG_PATH"]

with open("/template.json", encoding="utf-8") as f:
    config = json.load(f)

outbounds = []
proxy_tag = ""

if outbounds_file:
    with open(outbounds_file, encoding="utf-8") as f:
        proxy_outbounds = json.load(f)
    outbounds.extend(proxy_outbounds)
    for ob in proxy_outbounds:
        if ob.get("type") in ("urltest", "selector"):
            proxy_tag = ob["tag"]
            break
    if not proxy_tag and proxy_outbounds:
        proxy_tag = proxy_outbounds[0]["tag"]

if ssh_enabled:
    ssh_ob = {
        "tag": "ssh-exit",
        "type": "ssh",
        "server": os.environ["SSH_HOST"],
        "server_port": int(os.environ.get("SSH_PORT") or 22),
        "user": os.environ["SSH_USER"],
        "private_key_path": os.environ["SSH_KEY_PATH"],
    }
    if proxy_tag:
        ssh_ob["detour"] = proxy_tag
    outbounds.append(ssh_ob)
    final_outbound = "ssh-exit"
else:
    final_outbound = proxy_tag if proxy_tag else "direct"

outbounds.append({"type": "direct", "tag": "direct"})
config["outbounds"] = outbounds
config["route"]["final"] = final_outbound

for srv in config.get("dns", {}).get("servers", []):
    if srv.get("tag") == "remote-dns":
        if final_outbound == "direct":
            srv.pop("detour", None)
        else:
            srv["detour"] = final_outbound

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

hops = ["App", "TUN"]
if proxy_tag:
    hops.append(proxy_tag)
if ssh_enabled:
    hops.append("SSH")
elif not proxy_tag:
    hops.append("DIRECT (NO PROXY)")
hops.append("🌐")

print(" → ".join(hops))
PY
)

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Config built successfully"
echo "  ⚙️  Mode:       $PROXY_MODE"
if [ "$PROXY_MODE" = "sub" ]; then
  echo "  ⏱️  Test every: $SUB_TEST_INTERVAL"
fi
if [ "$SSH_ENABLED" = "true" ]; then
  echo "  🔑 SSH exit:   $SSH_USER@$SSH_HOST:$SSH_PORT"
else
  echo "  ⚠️  SSH exit:   DISABLED (IP leak risk!)"
fi
echo "  🛡️  Kill switch: strict_route=true"
echo "  🔗 Chain:      $CHAIN_DESC"
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
