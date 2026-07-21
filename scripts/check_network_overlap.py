#!/usr/bin/env python3
"""Fail when the requested Compose subnet overlaps an existing Docker network."""

from __future__ import annotations

import ipaddress
import json
import subprocess
import sys


def docker_networks() -> list[dict]:
    network_ids = subprocess.check_output(
        ["docker", "network", "ls", "-q"], text=True
    ).split()
    if not network_ids:
        return []

    output = subprocess.check_output(
        ["docker", "network", "inspect", *network_ids], text=True
    )
    return json.loads(output)


def configured_subnets(network: dict) -> list[ipaddress.IPv4Network | ipaddress.IPv6Network]:
    configs = (network.get("IPAM") or {}).get("Config") or []
    result = []
    for config in configs:
        subnet = config.get("Subnet")
        if subnet:
            result.append(ipaddress.ip_network(subnet, strict=False))
    return result


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: check_network_overlap.py <subnet> <managed-network-name>",
            file=sys.stderr,
        )
        return 2

    requested = ipaddress.ip_network(sys.argv[1], strict=False)
    managed_name = sys.argv[2]
    conflicts: list[str] = []

    try:
        networks = docker_networks()
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError) as error:
        print(f"Cannot inspect Docker networks: {error}", file=sys.stderr)
        return 2

    for network in networks:
        name = network.get("Name", "<unknown>")
        subnets = configured_subnets(network)

        if name == managed_name:
            if requested in subnets:
                continue
            rendered = ", ".join(str(subnet) for subnet in subnets) or "no subnet"
            conflicts.append(
                f"{name} already exists with {rendered}; recreate this project network"
            )
            continue

        for subnet in subnets:
            if requested.version == subnet.version and requested.overlaps(subnet):
                conflicts.append(f"{name} uses {subnet}")

    if conflicts:
        print(f"Docker subnet {requested} cannot be used:", file=sys.stderr)
        for conflict in conflicts:
            print(f"  - {conflict}", file=sys.stderr)
        return 1

    print(f"Docker subnet {requested} is available.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
