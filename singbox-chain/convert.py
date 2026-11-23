#!/usr/bin/env python3
"""
Convert Xray/V2Ray JSON configs or share URIs → sing-box outbounds.
Handles:
- Sanaei panel JSON format (array of configs with flat settings)
- Standard Xray/V2Ray JSON configs
- Native sing-box JSON configs
- Single or multi-line share URIs (plain text or base64-encoded):
  vless://, vmess://, trojan://, ss://

Supports: VLESS, VMess, Trojan, Shadowsocks
Transports: TCP (raw & HTTP header), WebSocket, gRPC, HTTP/2, HTTPUpgrade/XHTTP/SplitHTTP
Security: TLS, Reality, None
"""

from __future__ import annotations

import base64
import json
import sys
from urllib.parse import parse_qs, unquote, urlsplit


URI_SCHEMES = ("vless://", "vmess://", "trojan://", "ss://")


def decode_base64(data: str) -> str:
    """Decode standard or URL-safe base64, tolerating missing padding."""
    cleaned = "".join(data.strip().split())
    padding = (-len(cleaned)) % 4
    cleaned += "=" * padding
    try:
        return base64.urlsafe_b64decode(cleaned).decode("utf-8")
    except Exception:
        return base64.b64decode(cleaned).decode("utf-8")


# ─── Xray JSON converters ────────────────────────────────────────────────────

def convert_tls(stream: dict) -> dict | None:
    security = stream.get("security", "none")

    if security == "tls":
        tls_settings = stream.get("tlsSettings", {})
        tls: dict = {"enabled": True}
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
        transport: dict = {"type": "ws"}
        if ws.get("path"):
            transport["path"] = ws["path"]
        headers = ws.get("headers", {})
        if headers.get("Host"):
            transport["headers"] = {"Host": headers["Host"]}
        return transport

    elif network in ("xhttp", "splithttp", "httpupgrade"):
        # Xray XHTTP/SplitHTTP/HTTPUpgrade → sing-box httpupgrade
        xhttp = stream.get(
            "httpupgradeSettings",
            stream.get("xhttpSettings", stream.get("splithttpSettings", {})),
        )
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

    sb: dict = {
        "type": "vless",
        "tag": tag,
        "server": address,
        "server_port": int(port),
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

    sb: dict = {
        "type": "vmess",
        "tag": tag,
        "server": address,
        "server_port": int(port),
        "uuid": uuid,
        "security": settings.get("security", "auto"),
        "alter_id": int(settings.get("alterId", 0)),
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

    sb: dict = {
        "type": "trojan",
        "tag": tag,
        "server": address,
        "server_port": int(port),
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
        "server_port": int(server.get("port", 443)),
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


# ─── Share URI converters (vless://, vmess://, trojan://, ss://) ────────────

def _qget(params: dict[str, list[str]], *keys: str, default: str = "") -> str:
    for key in keys:
        vals = params.get(key)
        if vals and vals[0]:
            return vals[0]
    return default


def _build_uri_tls(
    params: dict[str, list[str]],
    default_security: str,
    fallback_sni: str,
) -> dict | None:
    security = _qget(params, "security", default=default_security).lower()
    if security in ("", "none"):
        return None

    sni = _qget(params, "sni", "peer", "host", default=fallback_sni)
    fp = _qget(params, "fp", "fingerprint")
    alpn_raw = _qget(params, "alpn")
    alpn = [a.strip() for a in alpn_raw.split(",") if a.strip()] if alpn_raw else []
    insecure = _qget(params, "allowInsecure", "insecure").lower() in ("1", "true", "yes")

    if security == "tls":
        tls: dict = {"enabled": True}
        if sni:
            tls["server_name"] = sni
        if alpn:
            tls["alpn"] = alpn
        if fp:
            tls["utls"] = {"enabled": True, "fingerprint": fp}
        if insecure:
            tls["insecure"] = True
        return tls

    if security == "reality":
        tls = {
            "enabled": True,
            "server_name": sni,
            "reality": {
                "enabled": True,
                "public_key": _qget(params, "pbk", "publicKey"),
                "short_id": _qget(params, "sid", "shortId"),
            },
        }
        if fp:
            tls["utls"] = {"enabled": True, "fingerprint": fp}
        return tls

    return None


def _build_uri_transport(params: dict[str, list[str]]) -> dict | None:
    net = _qget(params, "type", "net", default="tcp").lower()
    path = _qget(params, "path")
    host = _qget(params, "host")
    header_type = _qget(params, "headerType", default="none").lower()

    if net == "ws":
        transport: dict = {"type": "ws"}
        if path:
            transport["path"] = path
        if host:
            transport["headers"] = {"Host": host}
        return transport

    if net in ("xhttp", "splithttp", "httpupgrade"):
        transport = {"type": "httpupgrade"}
        if path:
            transport["path"] = path
        if host:
            transport["host"] = host
        return transport

    if net == "grpc":
        transport = {"type": "grpc"}
        svc = _qget(params, "serviceName", "path")
        if svc:
            transport["service_name"] = svc
        return transport

    if net in ("h2", "http"):
        transport = {"type": "http"}
        if path:
            transport["path"] = path
        if host:
            transport["host"] = [h.strip() for h in host.split(",") if h.strip()]
        return transport

    if net == "tcp" and header_type == "http":
        transport = {"type": "http"}
        if path:
            transport["path"] = path
        if host:
            transport["host"] = [h.strip() for h in host.split(",") if h.strip()]
        return transport

    return None


def parse_vless_uri(uri: str, tag: str) -> dict:
    parsed = urlsplit(uri)
    if not parsed.hostname:
        raise ValueError("Missing host in vless URI")
    uuid = unquote(parsed.username or "")
    if not uuid:
        raise ValueError("Missing UUID in vless URI")

    params = parse_qs(parsed.query, keep_blank_values=False)
    sb: dict = {
        "type": "vless",
        "tag": tag,
        "server": parsed.hostname,
        "server_port": parsed.port or 443,
        "uuid": uuid,
    }

    flow = _qget(params, "flow")
    if flow:
        sb["flow"] = flow

    tls = _build_uri_tls(params, default_security="none", fallback_sni=parsed.hostname)
    if tls:
        sb["tls"] = tls

    transport = _build_uri_transport(params)
    if transport:
        sb["transport"] = transport

    return sb


def parse_trojan_uri(uri: str, tag: str) -> dict:
    parsed = urlsplit(uri)
    if not parsed.hostname:
        raise ValueError("Missing host in trojan URI")
    password = unquote(parsed.username or "")
    if not password:
        raise ValueError("Missing password in trojan URI")

    params = parse_qs(parsed.query, keep_blank_values=False)
    sb: dict = {
        "type": "trojan",
        "tag": tag,
        "server": parsed.hostname,
        "server_port": parsed.port or 443,
        "password": password,
    }

    tls = _build_uri_tls(params, default_security="tls", fallback_sni=parsed.hostname)
    if tls:
        sb["tls"] = tls

    transport = _build_uri_transport(params)
    if transport:
        sb["transport"] = transport

    return sb


def parse_vmess_uri(uri: str, tag: str) -> dict:
    payload = uri[len("vmess://"):].split("#", 1)[0].strip()
    data = json.loads(decode_base64(payload))

    server = data.get("add", "")
    if not server:
        raise ValueError("Missing 'add' in vmess URI")

    sb: dict = {
        "type": "vmess",
        "tag": tag,
        "server": server,
        "server_port": int(data.get("port", 443)),
        "uuid": data.get("id", ""),
        "security": data.get("scy") or "auto",
        "alter_id": int(data.get("aid") or 0),
    }

    params: dict[str, list[str]] = {}
    if data.get("net"):
        params["type"] = [str(data["net"])]
    if data.get("type"):
        params["headerType"] = [str(data["type"])]
    if data.get("host"):
        params["host"] = [str(data["host"])]
    if data.get("path"):
        params["path"] = [str(data["path"])]
        params["serviceName"] = [str(data["path"])]
    if str(data.get("tls", "")).lower() == "tls":
        params["security"] = ["tls"]
    if data.get("sni"):
        params["sni"] = [str(data["sni"])]
    if data.get("alpn"):
        params["alpn"] = [str(data["alpn"])]
    if data.get("fp"):
        params["fp"] = [str(data["fp"])]

    tls = _build_uri_tls(params, default_security="none", fallback_sni=server)
    if tls:
        sb["tls"] = tls

    transport = _build_uri_transport(params)
    if transport:
        sb["transport"] = transport

    return sb


def parse_ss_uri(uri: str, tag: str) -> dict:
    body = uri[len("ss://"):].split("#", 1)[0].strip()
    # Drop query params (e.g. plugin=...)
    body = body.split("?", 1)[0]

    if "@" in body:
        userinfo, hostport = body.rsplit("@", 1)
        userinfo = unquote(userinfo)
        if ":" in userinfo:
            method, password = userinfo.split(":", 1)
        else:
            decoded = decode_base64(userinfo)
            method, password = decoded.split(":", 1)
    else:
        decoded = decode_base64(body)
        if "@" not in decoded:
            raise ValueError("Invalid Shadowsocks URI")
        creds, hostport = decoded.rsplit("@", 1)
        method, password = creds.split(":", 1)

    parsed_hp = urlsplit(f"//{hostport}")
    if not parsed_hp.hostname or not parsed_hp.port:
        raise ValueError(f"Invalid host:port in Shadowsocks URI: {hostport!r}")

    return {
        "type": "shadowsocks",
        "tag": tag,
        "server": parsed_hp.hostname,
        "server_port": parsed_hp.port,
        "method": method,
        "password": password,
    }


URI_PARSERS = {
    "vless://": parse_vless_uri,
    "vmess://": parse_vmess_uri,
    "trojan://": parse_trojan_uri,
    "ss://": parse_ss_uri,
}


def extract_uris(text: str) -> list[str]:
    """Extract proxy URIs from plain text or base64-encoded subscription text."""
    tokens = [tok.strip() for tok in text.split() if tok.strip()]
    direct_uris = [t for t in tokens if t.lower().startswith(URI_SCHEMES)]
    if direct_uris:
        return direct_uris

    # Fallback: try base64-encoded URI subscription
    try:
        decoded = decode_base64(text)
    except Exception:
        return []
    dec_tokens = [tok.strip() for tok in decoded.split() if tok.strip()]
    return [t for t in dec_tokens if t.lower().startswith(URI_SCHEMES)]


def convert_uris(uris: list[str]) -> list[dict]:
    outbounds = []
    for i, uri in enumerate(uris):
        lower = uri.lower()
        parser = None
        for prefix, fn in URI_PARSERS.items():
            if lower.startswith(prefix):
                parser = fn
                break
        if not parser:
            continue
        try:
            outbounds.append(parser(uri, f"proxy-{i}"))
        except Exception as e:
            print(f"⚠️  Error parsing URI [{i}]: {e}", file=sys.stderr)
    return outbounds


# ─── Common post-processing ──────────────────────────────────────────────────

def deduplicate(outbounds: list[dict]) -> list[dict]:
    """Remove duplicate outbounds (same server:port:type)."""
    seen = set()
    unique = []
    for ob in outbounds:
        key = (ob.get("type", ""), ob.get("server", ""), ob.get("server_port", 0))
        if key not in seen:
            seen.add(key)
            unique.append(ob)
        else:
            print(
                f"🔄 Dedup: skipping duplicate {ob['tag']} ({key[1]}:{key[2]})",
                file=sys.stderr,
            )
    return unique


def write_output(outbounds: list[dict], output_path: str | None) -> None:
    result = json.dumps(outbounds, indent=2, ensure_ascii=False)
    if output_path:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"💾 Saved to {output_path}", file=sys.stderr)
    else:
        print(result)


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: convert.py <input> [output.json]", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    with open(input_path, encoding="utf-8") as f:
        raw_text = f.read().strip()

    if not raw_text:
        print("❌ Empty proxy input!", file=sys.stderr)
        sys.exit(1)

    # 1. Try JSON input (sing-box JSON or Xray/V2Ray JSON)
    parsed_json = None
    try:
        parsed_json = json.loads(raw_text)
    except json.JSONDecodeError:
        parsed_json = None

    if parsed_json is not None:
        # Check if already sing-box format
        if isinstance(parsed_json, dict):
            first_ob = (parsed_json.get("outbounds") or [{}])[0]
            if isinstance(first_ob, dict) and "type" in first_ob and "protocol" not in first_ob:
                print("✅ Already in sing-box format", file=sys.stderr)
                outbounds = [
                    ob for ob in parsed_json["outbounds"]
                    if ob.get("type") not in ("direct", "block", "dns")
                ]
                write_output(outbounds, output_path)
                return

        print("🔄 Converting Xray JSON → sing-box...", file=sys.stderr)
        outbounds = convert_config(parsed_json)
    else:
        # 2. Try share URI(s) (plain or base64-encoded)
        uris = extract_uris(raw_text)
        if not uris:
            print("❌ Unsupported input format (not JSON or valid vless/vmess/trojan/ss URI)", file=sys.stderr)
            sys.exit(1)
        print(f"🔄 Converting {len(uris)} share URI(s) → sing-box...", file=sys.stderr)
        outbounds = convert_uris(uris)

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
        print(f"➕ Added 'auto' urltest selector over {len(outbounds) - 1} servers", file=sys.stderr)

    write_output(outbounds, output_path)


if __name__ == "__main__":
    main()
