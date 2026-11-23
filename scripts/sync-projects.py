#!/usr/bin/env python3
"""Generate docker-compose.override.yaml volume mounts from PROJECTS in .env."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"
OVERRIDE_FILE = ROOT / "docker-compose.override.yaml"


def read_projects_value() -> str:
    if "PROJECTS" in os.environ:
        return os.environ["PROJECTS"]
    if not ENV_FILE.exists():
        return ""
    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        if key.strip() == "PROJECTS":
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
                val = val[1:-1]
            return val
    return ""


def parse_entry(entry: str) -> tuple[str, str]:
    """Parse '/host/path' or '/host/path:custom-name' into (host_path, container_path)."""
    has_alias = ":" in entry and not (
        len(entry) >= 2 and entry[1] == ":" and ":" not in entry[2:]
    )
    if has_alias:
        host_raw, alias = entry.rsplit(":", 1)
        host_raw = host_raw.strip()
        alias = alias.strip().strip("/")
    else:
        host_raw = entry.strip()
        alias = ""

    if not host_raw:
        raise ValueError(f"Empty host path in entry: {entry!r}")

    host_expanded = os.path.expanduser(host_raw)
    if host_expanded != "/":
        host_expanded = host_expanded.rstrip("/")

    if not alias:
        p = Path(host_expanded)
        alias = p.name if p.name not in ("", ".", "..") else p.resolve().name

    if not alias or ".." in Path(alias).parts:
        raise ValueError(f"Invalid target mount name {alias!r} in entry: {entry!r}")

    return host_expanded, f"/workspace/{alias}"


def main() -> int:
    raw = read_projects_value().strip()
    entries = [item.strip() for item in raw.split(",") if item.strip()]

    if not entries:
        if OVERRIDE_FILE.exists():
            OVERRIDE_FILE.unlink()
        return 0

    mounts: list[tuple[str, str]] = []
    seen_targets: dict[str, str] = {}

    for entry in entries:
        try:
            host_path, container_path = parse_entry(entry)
        except ValueError as exc:
            print(f"❌ {exc}", file=sys.stderr)
            return 1

        if container_path in seen_targets:
            print(
                f"❌ Duplicate workspace target {container_path} for "
                f"{seen_targets[container_path]!r} and {host_path!r}. "
                f"Specify a custom name with '/path:custom-name'.",
                file=sys.stderr,
            )
            return 1

        seen_targets[container_path] = host_path
        mounts.append((host_path, container_path))

        check_path = Path(host_path)
        if not check_path.is_absolute():
            check_path = ROOT / check_path
        if not check_path.exists():
            print(
                f"⚠️  Project path does not exist (Docker will create an empty dir): {host_path}",
                file=sys.stderr,
            )

    lines = [
        "# Auto-generated from PROJECTS in .env — do not edit manually.",
        "# Regenerated automatically on `make up` / `make build` (or run `make sync-projects`).",
        "services:",
        "  t3code:",
        "    volumes:",
    ]
    for host_path, container_path in mounts:
        spec = f"{host_path}:{container_path}".replace("$", "$$")
        lines.append(f"      - {json.dumps(spec)}")

    OVERRIDE_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
