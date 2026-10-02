"""Helpers to discover local IPv4 networks and validate client origin."""

from __future__ import annotations

import ipaddress
import socket

import psutil


def get_local_ipv4_networks() -> list[ipaddress.IPv4Network]:
    """Return the IPv4 network of every active, non-loopback interface."""
    networks: list[ipaddress.IPv4Network] = []
    stats = psutil.net_if_stats()
    for iface, addrs in psutil.net_if_addrs().items():
        iface_stats = stats.get(iface)
        if iface_stats is None or not iface_stats.isup:
            continue
        for addr in addrs:
            if addr.family != socket.AF_INET or not addr.netmask:
                continue
            try:
                if ipaddress.IPv4Address(addr.address).is_loopback:
                    continue
                networks.append(
                    ipaddress.IPv4Network(f"{addr.address}/{addr.netmask}", strict=False)
                )
            except ValueError:
                continue
    return networks


def get_primary_ipv4() -> str:
    """Best-effort guess of the machine's primary IPv4 address."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            # No traffic is actually sent; this just asks the OS which local
            # address would be used to reach an external host.
            sock.connect(("8.8.8.8", 80))
            return str(sock.getsockname()[0])
    except OSError:
        pass
    # Fallback: first non-loopback interface address.
    for addrs in psutil.net_if_addrs().values():
        for addr in addrs:
            if addr.family != socket.AF_INET:
                continue
            try:
                if not ipaddress.IPv4Address(addr.address).is_loopback:
                    return str(addr.address)
            except ValueError:
                continue
    return "127.0.0.1"


def is_same_subnet(client_ip: str) -> bool:
    """True if *client_ip* belongs to a local network (loopback always allowed)."""
    try:
        addr = ipaddress.ip_address(client_ip)
    except ValueError:
        return False
    if addr.is_loopback:
        return True
    if isinstance(addr, ipaddress.IPv4Address):
        return any(addr in network for network in get_local_ipv4_networks())
    return False
