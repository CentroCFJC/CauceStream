"""Wake-on-LAN magic packet, shared by every controller that has to boot
a fully-off device. Ported from CAUCE/Control (google_tv_sala.py): the
packet goes to broadcast and to the device IP, on each configured port.
"""

import socket
from collections.abc import Iterable


def send_wake_on_lan(mac_address: str, ip: str, ports: Iterable[int] = (9, 7)) -> None:
    """Send a WoL magic packet for `mac_address` (broadcast + unicast)."""
    mac = mac_address.replace(":", "-").replace(".", "-").upper()
    if len(mac) != 17:
        raise ValueError(f"invalid MAC address: {mac_address}")
    mac_bytes = bytes.fromhex(mac.replace("-", ""))
    packet = b"\xff" * 6 + mac_bytes * 16

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    try:
        for dest in ("<broadcast>", "255.255.255.255", ip):
            for port in ports:
                try:
                    sock.sendto(packet, (dest, port))
                except OSError:
                    pass
    finally:
        sock.close()
