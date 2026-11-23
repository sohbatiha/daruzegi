#!/usr/bin/env python3
"""
Convert Xray/V2Ray JSON config → sing-box outbounds.
Handles Sanaei panel format (array of configs with flat settings).

Supports: VLESS, VMess, Trojan, Shadowsocks
Transports: TCP, WebSocket, gRPC, HTTP/2, XHTTP/SplitHTTP
Security: TLS, Reality, None
"""

import json
import sys


def convert_tls(stream: dict) -> dict | None:
    security = stream.get("security", "none")

    if security == "tls":
        tls_settings = stream.get("tlsSettings", {})
        tls = {"enabled": True}
        if tls_settings.get("serverName"):
            tls["server_name"] = tls_settings["serverName"]
        if tls_settings.get("alpn"):
            tls["alpn"] = tls_settings["alpn"]
        if tls_settings.get("fingerprint"):
            tls["utls"] = {
                "enabled": True,
                "fingerprint": tls_settings["fingerprint"],
            }
        if tls_settings.get("allowInsecure"):
            tls["insecure"] = True
        return tls

    elif security == "reality":
        reality_settings = stream.get("realitySettings", {})
        tls = {
            "enabled": True,
            "server_name": reality_settings.get("serverName", ""),
            "reality": {
                "enabled": True,
                "public_key": reality_settings.get("publicKey", ""),
                "short_id": reality_settings.get("shortId", ""),
            },
        }
        if reality_settings.get("fingerprint"):
            tls["utls"] = {
                "enabled": True,
                "fingerprint": reality_settings["fingerprint"],
            }
        return tls

    return None


def convert_transport(stream: dict) -> dict | None:
    network = stream.get("network", "tcp")

    if network == "ws":
        ws = stream.get("wsSettings", {})
        transport = {"type": "ws"}
        if ws.get("path"):
            transport["path"] = ws["path"]
        headers = ws.get("headers", {})
        if headers.get("Host"):
            transport["headers"] = {"Host": headers["Host"]}
        return transport

    elif network in ("xhttp", "splithttp"):
        # Xray XHTTP/SplitHTTP → sing-box httpupgrade or http
        xhttp = stream.get("xhttpSettings", stream.get("splithttpSettings", {}))
        transport = {"type": "httpupgrade"}
        if xhttp.get("path"):
            transport["path"] = xhttp["path"]
        if xhttp.get("host"):
            transport["host"] = xhttp["host"]
        return transport

    elif network == "grpc":
        grpc = stream.get("grpcSettings", {})
        transport = {"type": "grpc"}
        if grpc.get("serviceName"):
            transport["service_name"] = grpc["serviceName"]
        return transport

    elif network in ("h2", "http"):
        h2 = stream.get("httpSettings", {})
        transport = {"type": "http"}
        if h2.get("path"):
            transport["path"] = h2["path"]
        if h2.get("host"):
            transport["host"] = h2["host"]
        return transport

    elif network == "tcp":
        tcp = stream.get("tcpSettings", {})
        header = tcp.get("header", {})
        if header.get("type") == "http":
            transport = {"type": "http"}
            req = header.get("request", {})
            if req.get("path"):
                p = req["path"]
                transport["path"] = p[0] if isinstance(p, list) else p
            if req.get("headers", {}).get("Host"):
                host = req["headers"]["Host"]
                transport["host"] = host if isinstance(host, list) else [host]
            return transport

    return None


def extract_server_info(outbound: dict) -> tuple[str, int, str]:
    """Extract (address, port, uuid/password) from either standard or flat settings."""
    settings = outbound.get("settings", {})
    protocol = outbound.get("protocol", "")

    # Standard Xray format: vnext[0] for vless/vmess
    if "vnext" in settings:
        vnext = settings["vnext"][0]
        users = vnext.get("users", [{}])[0]
        return vnext["address"], vnext["port"], users.get("id", "")

    # Standard Xray format: servers[0] for trojan/shadowsocks
    if "servers" in settings:
        server = settings["servers"][0]
        pwd_key = "password" if protocol in ("trojan", "shadowsocks") else "id"
        return server["address"], server["port"], server.get(pwd_key, "")

    # Sanaei panel flat format: address/port/id directly in settings
    if "address" in settings:
        return (
            settings["address"],
            settings.get("port", 443),
            settings.get("id", settings.get("password", "")),
        )

    raise ValueError(f"Cannot extract server info from: {json.dumps(settings)[:200]}")


def convert_vless(outbound: dict, tag: str) -> dict:
    address, port, uuid = extract_server_info(outbound)
    stream = outbound.get("streamSettings", {})
    settings = outbound.get("settings", {})

    sb = {
        "type": "vless",
        "tag": tag,
        "server": address,
        "server_port": port,
        "uuid": uuid,
    }

    # Flow (xtls-rprx-vision etc)
    flow = settings.get("flow", "")
    if not flow and "vnext" in settings:
        flow = settings["vnext"][0].get("users", [{}])[0].get("flow", "")
    if flow:
        sb["flow"] = flow

    tls = convert_tls(stream)
    if tls:
        # If no server_name in TLS, use address or xhttp host
        if "server_name" not in tls or not tls["server_name"]:
            xhttp = stream.get("xhttpSettings", stream.get("splithttpSettings", {}))
            tls["server_name"] = xhttp.get("host", address)
        sb["tls"] = tls

    transport = convert_transport(stream)
    if transport:
        sb["transport"] = transport

    return sb


def convert_vmess(outbound: dict, tag: str) -> dict:
    address, port, uuid = extract_server_info(outbound)
    stream = outbound.get("streamSettings", {})
    settings = outbound.get("settings", {})

    sb = {
        "type": "vmess",
        "tag": tag,
        "server": address,
        "server_port": port,
        "uuid": uuid,
        "security": settings.get("security", "auto"),
        "alter_id": settings.get("alterId", 0),
    }

    tls = convert_tls(stream)
    if tls:
        sb["tls"] = tls

    transport = convert_transport(stream)
    if transport:
        sb["transport"] = transport

    return sb


def convert_trojan(outbound: dict, tag: str) -> dict:
    address, port, password = extract_server_info(outbound)
    stream = outbound.get("streamSettings", {})

    sb = {
        "type": "trojan",
        "tag": tag,
        "server": address,
        "server_port": port,
        "password": password,
    }

    tls = convert_tls(stream)
    if tls:
        sb["tls"] = tls

    transport = convert_transport(stream)
    if transport:
        sb["transport"] = transport

    return sb


def convert_shadowsocks(outbound: dict, tag: str) -> dict:
    settings = outbound.get("settings", {})

    if "servers" in settings:
        server = settings["servers"][0]
    else:
        server = settings

    return {
        "type": "shadowsocks",
        "tag": tag,
        "server": server.get("address", ""),
        "server_port": server.get("port", 443),
        "method": server.get("method", "aes-256-gcm"),
        "password": server.get("password", ""),
    }


CONVERTERS = {
    "vless": convert_vless,
    "vmess": convert_vmess,
    "trojan": convert_trojan,
    "shadowsocks": convert_shadowsocks,
}

SKIP_PROTOCOLS = {"freedom", "blackhole", "dns", "loopback"}


def convert_config(xray_config: dict | list) -> list[dict]:
    """Convert Xray config(s) to sing-box outbounds."""

    # Handle Sanaei format: array of full configs
    if isinstance(xray_config, list):
        all_outbounds = []
        for i, config in enumerate(xray_config):
            if not isinstance(config, dict):
                continue
            for ob in config.get("outbounds", []):
                protocol = ob.get("protocol", "")
                if protocol in SKIP_PROTOCOLS:
                    continue
                converter = CONVERTERS.get(protocol)
                if not converter:
                    print(f"⚠️  Skipping unsupported protocol: {protocol}", file=sys.stderr)
                    continue
                try:
                    tag = f"proxy-{i}"
                    sb_ob = converter(ob, tag)
                    all_outbounds.append(sb_ob)
                except Exception as e:
                    print(f"⚠️  Error converting [{i}]: {e}", file=sys.stderr)
        return all_outbounds

    # Standard format: single config object
    sb_outbounds = []
    for i, ob in enumerate(xray_config.get("outbounds", [])):
        protocol = ob.get("protocol", "")
        if protocol in SKIP_PROTOCOLS:
            continue
        converter = CONVERTERS.get(protocol)
        if not converter:
            print(f"⚠️  Skipping unsupported protocol: {protocol}", file=sys.stderr)
            continue
        try:
            tag = ob.get("tag", f"proxy-{i}")
            sb_ob = converter(ob, tag)
            sb_outbounds.append(sb_ob)
        except Exception as e:
            print(f"⚠️  Error converting {ob.get('tag', i)}: {e}", file=sys.stderr)

    return sb_outbounds


def deduplicate(outbounds: list[dict]) -> list[dict]:
    """Remove duplicate outbounds (same server:port)."""
    seen = set()
    unique = []
    for ob in outbounds:
        key = (ob.get("server", ""), ob.get("server_port", 0))
        if key not in seen:
            seen.add(key)
            unique.append(ob)
        else:
            print(f"🔄 Dedup: skipping duplicate {ob['tag']} ({key[0]}:{key[1]})", file=sys.stderr)
    return unique


def main():
    if len(sys.argv) < 2:
        print("Usage: convert.py <input.json> [output.json]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    with open(input_path) as f:
        xray_config = json.load(f)

    # Check if already sing-box format
    if isinstance(xray_config, dict):
        first_ob = (xray_config.get("outbounds") or [{}])[0]
        if "type" in first_ob and "protocol" not in first_ob:
            print("✅ Already in sing-box format", file=sys.stderr)
            outbounds = [
                ob for ob in xray_config["outbounds"]
                if ob.get("type") not in ("direct", "block", "dns")
            ]
            result = json.dumps(outbounds, indent=2, ensure_ascii=False)
            if output_path:
                with open(output_path, "w") as f:
                    f.write(result)
            else:
                print(result)
            return

    print("🔄 Converting Xray → sing-box...", file=sys.stderr)
    outbounds = convert_config(xray_config)
    outbounds = deduplicate(outbounds)

    if not outbounds:
        print("❌ No proxy outbounds found!", file=sys.stderr)
        sys.exit(1)

    print(f"✅ Converted {len(outbounds)} outbound(s)", file=sys.stderr)

    # Add urltest selector if multiple outbounds
    if len(outbounds) > 1:
        selector = {
            "type": "urltest",
            "tag": "auto",
            "outbounds": [ob["tag"] for ob in outbounds],
            "url": "https://www.gstatic.com/generate_204",
            "interval": "5m",
        }
        outbounds.insert(0, selector)
        print(f"➕ Added 'auto' urltest selector over {len(outbounds)-1} servers", file=sys.stderr)

    result = json.dumps(outbounds, indent=2, ensure_ascii=False)

    if output_path:
        with open(output_path, "w") as f:
            f.write(result)
        print(f"💾 Saved to {output_path}", file=sys.stderr)
    else:
        print(result)


if __name__ == "__main__":
    main()
